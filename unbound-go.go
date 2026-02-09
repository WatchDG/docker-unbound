package main

import (
	"fmt"
	"io/ioutil"
	"net"
	"os"
	// "os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func getEnv(key, defaultValue string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultValue
}

func escapeReplacement(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\\", "\\\\"), "&", "\\&")
}

func resolveHost(host string) (string, error) {
	if ip := net.ParseIP(host); ip != nil {
		return host, nil
	}

	addrs, err := net.LookupHost(host)
	if err != nil || len(addrs) == 0 {
		return "", fmt.Errorf("unable to resolve forward-addr host: %s", host)
	}
	return addrs[0], nil
}

func main() {
	template := getEnv("TEMPLATE", "/etc/unbound/unbound.conf.template")
	conf := getEnv("CONF", "/etc/unbound/unbound.conf")

	data, err := ioutil.ReadFile(template)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading template: %v\n", err)
		os.Exit(1)
	}

	content := string(data)

	replacements := map[string]string{
		"__SERVER__USERNAME__":                 getEnv("UNBOUND__SERVER__USERNAME", ""),
		"__SERVER__PORT__":                     getEnv("UNBOUND__SERVER__PORT", "5353"),
		"__SERVER__NUM_THREADS__":              getEnv("UNBOUND__SERVER__NUM_THREADS", "2"),
		"__SERVER__SO_RCVBUF__":                getEnv("UNBOUND__SERVER__SO_RCVBUF", "0"),
		"__SERVER__SO_SNDBUF__":                getEnv("UNBOUND__SERVER__SO_SNDBUF", "0"),
		"__SERVER__DO_NOT_QUERY_LOCALHOST__":   getEnv("UNBOUND__SERVER__DO_NOT_QUERY_LOCALHOST", "yes"),
		"__SERVER__VERBOSITY__":                getEnv("UNBOUND__SERVER__VERBOSITY", "1"),
		"__SERVER__LOG_QUERIES__":              getEnv("UNBOUND__SERVER__LOG_QUERIES", "yes"),
		"__SERVER__USE_SYSLOG__":               getEnv("UNBOUND__SERVER__USE_SYSLOG", "no"),
		"__SERVER__LOGFILE__":                  getEnv("UNBOUND__SERVER__LOGFILE", "\"\""),
		"__SERVER__DIRECTORY__":                getEnv("UNBOUND__SERVER__DIRECTORY", "/var/unbound"),
		"__SERVER__CHROOT__":                   getEnv("UNBOUND__SERVER__CHROOT", ""),
		"__SERVER__INTERFACE__":                getEnv("UNBOUND__SERVER__INTERFACE", "0.0.0.0"),
		"__SERVER__DO_IP4__":                   getEnv("UNBOUND__SERVER__DO_IP4", "yes"),
		"__SERVER__DO_IP6__":                   getEnv("UNBOUND__SERVER__DO_IP6", "no"),
		"__SERVER__DO_UDP__":                   getEnv("UNBOUND__SERVER__DO_UDP", "yes"),
		"__SERVER__DO_TCP__":                   getEnv("UNBOUND__SERVER__DO_TCP", "yes"),
		"__SERVER__USE_CAPS_FOR_ID__":          getEnv("UNBOUND__SERVER__USE_CAPS_FOR_ID", "yes"),
		"__SERVER__PREFETCH__":                 getEnv("UNBOUND__SERVER__PREFETCH", "yes"),
		"__SERVER__QNAME_MINIMISATION__":       getEnv("UNBOUND__SERVER__QNAME_MINIMISATION", "yes"),
		"__SERVER__MINIMAL_RESPONSES__":         getEnv("UNBOUND__SERVER__MINIMAL_RESPONSES", "yes"),
		"__SERVER__HIDE_IDENTITY__":            getEnv("UNBOUND__SERVER__HIDE_IDENTITY", "yes"),
		"__SERVER__HIDE_VERSION__":              getEnv("UNBOUND__SERVER__HIDE_VERSION", "yes"),
		"__SERVER__HARDEN_GLUE__":               getEnv("UNBOUND__SERVER__HARDEN_GLUE", "yes"),
		"__SERVER__HARDEN_REFERRAL_PATH__":     getEnv("UNBOUND__SERVER__HARDEN_REFERRAL_PATH", "yes"),
		"__SERVER__CACHE_MIN_TTL__":            getEnv("UNBOUND__SERVER__CACHE_MIN_TTL", "60"),
		"__SERVER__CACHE_MAX_TTL__":            getEnv("UNBOUND__SERVER__CACHE_MAX_TTL", "86400"),
		"__SERVER__MSG_CACHE_SIZE__":          getEnv("UNBOUND__SERVER__MSG_CACHE_SIZE", "64m"),
		"__SERVER__RRSET_CACHE_SIZE__":         getEnv("UNBOUND__SERVER__RRSET_CACHE_SIZE", "64m"),
		"__SERVER__UNWANTED_REPLY_THRESHOLD__": getEnv("UNBOUND__SERVER__UNWANTED_REPLY_THRESHOLD", "10000"),
	}

	for placeholder, value := range replacements {
		escapedValue := escapeReplacement(value)
		content = strings.ReplaceAll(content, placeholder, escapedValue)
	}

	forwardAddr := getEnv("UNBOUND__FORWARD_ZONE__FORWARD_ADDR", "")
	if forwardAddr != "" {
		forwardName := getEnv("UNBOUND__FORWARD_ZONE__NAME", ".")
		forwardTLS := getEnv("UNBOUND__FORWARD_ZONE__FORWARD_TLS_UPSTREAM", "no")

		forwardHost := forwardAddr
		forwardPort := ""
		if strings.Contains(forwardAddr, "@") {
			parts := strings.SplitN(forwardAddr, "@", 2)
			forwardHost = parts[0]
			forwardPort = parts[1]
		}

		resolvedHost, err := resolveHost(forwardHost)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			os.Exit(1)
		}

		forwardAddrResolved := resolvedHost
		if forwardPort != "" {
			forwardAddrResolved = fmt.Sprintf("%s@%s", resolvedHost, forwardPort)
		}

		forwardZone := fmt.Sprintf("\nforward-zone:\n    name: \"%s\"\n    forward-addr: %s\n    forward-tls-upstream: %s\n",
			forwardName, forwardAddrResolved, forwardTLS)
		content += forwardZone
	}

	if err := os.MkdirAll(filepath.Dir(conf), 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating config directory: %v\n", err)
		os.Exit(1)
	}

	if err := ioutil.WriteFile(conf, []byte(content), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing config: %v\n", err)
		os.Exit(1)
	}

	serverDirectory := getEnv("UNBOUND__SERVER__DIRECTORY", "/var/unbound")
	if err := os.MkdirAll(serverDirectory, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating server directory: %v\n", err)
		os.Exit(1)
	}

	args := []string{"/usr/sbin/unbound", "-d", "-c", conf}
	if err := syscall.Exec("/usr/sbin/unbound", args, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "Error executing unbound: %v\n", err)
		os.Exit(1)
	}
}
