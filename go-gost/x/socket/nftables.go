package socket

import (
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"strconv"
	"strings"
)

const nftForwardTable = "flvx_forward"

type nftForwardRequest struct {
	ID                  int64    `json:"id"`
	Proto               string   `json:"proto"`
	ListenIP            string   `json:"listenIP,omitempty"`
	ListenPort          int      `json:"listenPort"`
	Targets             []string `json:"targets,omitempty"`
	LoadBalanceStrategy string   `json:"loadBalanceStrategy,omitempty"`
	RemoteIP            string   `json:"remoteIP"`
	RemotePort          int      `json:"remotePort"`
	MaxConn             int      `json:"maxConn"`
	IPMaxConn           int      `json:"ipMaxConn"`
}

func (w *WebSocketReporter) handleNftablesApply(data interface{}) error {
	var req nftForwardRequest
	if err := decodeNftForwardRequest(data, &req); err != nil {
		return err
	}
	return ApplyNftForward(req)
}

func (w *WebSocketReporter) handleNftablesDelete(data interface{}) error {
	var req struct {
		ID int64 `json:"id"`
	}
	if err := decodeNftForwardRequest(data, &req); err != nil {
		return err
	}
	if req.ID <= 0 {
		return fmt.Errorf("invalid nftables forward id")
	}
	return DeleteNftForward(req.ID)
}

func decodeNftForwardRequest(data interface{}, out interface{}) error {
	raw, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("serialize nftables request: %w", err)
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("parse nftables request: %w", err)
	}
	return nil
}

func ApplyNftForward(req nftForwardRequest) error {
	req.Proto = strings.ToLower(strings.TrimSpace(req.Proto))
	if req.ID <= 0 {
		return fmt.Errorf("invalid nftables forward id")
	}
	if req.Proto != "tcp" && req.Proto != "udp" {
		return fmt.Errorf("unsupported nftables proto %q", req.Proto)
	}
	if len(req.Targets) > 0 && strings.TrimSpace(req.RemoteIP) == "" {
		host, port, err := splitNftTargetHostPort(req.Targets[0])
		if err != nil {
			return err
		}
		req.RemoteIP = host
		req.RemotePort = port
	}
	if req.ListenPort <= 0 || req.ListenPort > 65535 || req.RemotePort <= 0 || req.RemotePort > 65535 {
		return fmt.Errorf("invalid nftables port")
	}
	remoteIP := net.ParseIP(strings.Trim(req.RemoteIP, "[]"))
	if remoteIP == nil {
		return fmt.Errorf("remoteIP must be an IP address")
	}
	var listenIP net.IP
	if strings.TrimSpace(req.ListenIP) != "" {
		listenIP = net.ParseIP(strings.Trim(req.ListenIP, "[]"))
		if listenIP == nil {
			return fmt.Errorf("listenIP must be an IP address")
		}
	}

	if err := ensureNftForwardTable(); err != nil {
		return err
	}
	if err := cleanupNftForwardChain(nftForwardChainName(req.ID, req.Proto)); err != nil {
		return err
	}
	if err := cleanupNftForwardChain(nftForwardPostChainName(req.ID, req.Proto)); err != nil {
		return err
	}

	script := buildApplyNftForwardScript(req, remoteIP, listenIP)
	return runNftScript(script)
}

func DeleteNftForward(forwardID int64) error {
	if forwardID <= 0 {
		return fmt.Errorf("invalid nftables forward id")
	}
	for _, proto := range []string{"tcp", "udp"} {
		if err := cleanupNftForwardChain(nftForwardChainName(forwardID, proto)); err != nil {
			return err
		}
		if err := cleanupNftForwardChain(nftForwardPostChainName(forwardID, proto)); err != nil {
			return err
		}
	}
	return nil
}

func splitNftTargetHostPort(target string) (string, int, error) {
	host, portText, err := net.SplitHostPort(target)
	if err != nil {
		return "", 0, err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port <= 0 || port > 65535 {
		return "", 0, fmt.Errorf("invalid nftables target port %q", portText)
	}
	host = strings.Trim(host, "[]")
	if net.ParseIP(host) == nil {
		return "", 0, fmt.Errorf("nftables forward mode requires a valid IP target")
	}
	return host, port, nil
}

func buildApplyNftForwardScript(req nftForwardRequest, remoteIP net.IP, listenIP net.IP) string {
	family := "ip"
	if remoteIP.To4() == nil {
		family = "ip6"
	}

	preChain := nftForwardChainName(req.ID, req.Proto)
	postChain := nftForwardPostChainName(req.ID, req.Proto)
	dnatTarget := nftAddress(remoteIP) + ":" + strconv.Itoa(req.RemotePort)

	var b strings.Builder
	b.WriteString(fmt.Sprintf("add chain inet %s %s { type nat hook prerouting priority dstnat; policy accept; }\n", nftForwardTable, preChain))
	b.WriteString(fmt.Sprintf("add chain inet %s %s { type nat hook postrouting priority srcnat; policy accept; }\n", nftForwardTable, postChain))

	baseMatch := nftForwardMatch(req, listenIP)
	if req.Proto == "tcp" && req.IPMaxConn > 0 {
		b.WriteString(fmt.Sprintf("add rule inet %s %s %s meter %s { %s saddr ct count over %d } drop\n", nftForwardTable, preChain, baseMatch, nftForwardMeterName(req.ID, req.Proto), family, req.IPMaxConn))
	}
	if req.Proto == "tcp" && req.MaxConn > 0 {
		b.WriteString(fmt.Sprintf("add rule inet %s %s %s ct count over %d drop\n", nftForwardTable, preChain, baseMatch, req.MaxConn))
	}
	b.WriteString(fmt.Sprintf("add rule inet %s %s %s dnat %s to %s\n", nftForwardTable, preChain, baseMatch, family, dnatTarget))
	b.WriteString(fmt.Sprintf("add rule inet %s %s meta l4proto %s %s daddr %s %s dport %d masquerade\n", nftForwardTable, postChain, req.Proto, family, nftAddress(remoteIP), req.Proto, req.RemotePort))
	return b.String()
}

func nftForwardMatch(req nftForwardRequest, listenIP net.IP) string {
	parts := []string{"meta", "l4proto", req.Proto, req.Proto, "dport", strconv.Itoa(req.ListenPort)}
	if listenIP != nil {
		family := "ip"
		if listenIP.To4() == nil {
			family = "ip6"
		}
		parts = append([]string{family, "daddr", listenIP.String()}, parts...)
	}
	return strings.Join(parts, " ")
}

func nftAddress(ip net.IP) string {
	if ip.To4() != nil {
		return ip.String()
	}
	return "[" + ip.String() + "]"
}

func nftForwardChainName(forwardID int64, proto string) string {
	if proto == "tcp" {
		return fmt.Sprintf("fwd_%d", forwardID)
	}
	return fmt.Sprintf("fwd_%d_%s", forwardID, proto)
}

func nftForwardPostChainName(forwardID int64, proto string) string {
	if proto == "tcp" {
		return fmt.Sprintf("fwd_%d_post", forwardID)
	}
	return fmt.Sprintf("fwd_%d_%s_post", forwardID, proto)
}

func nftForwardMeterName(forwardID int64, proto string) string {
	return fmt.Sprintf("fwd_%d_%s_ip_conn", forwardID, proto)
}

func runNftScript(script string) error {
	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(script)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft failed: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func cleanupNftForwardChain(chain string) error {
	if err := runNftScriptIgnoreMissing(fmt.Sprintf("flush chain inet %s %s\n", nftForwardTable, chain)); err != nil {
		return err
	}
	return runNftScriptIgnoreMissing(fmt.Sprintf("delete chain inet %s %s\n", nftForwardTable, chain))
}

func runNftScriptIgnoreMissing(script string) error {
	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(script)
	output, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	msg := strings.TrimSpace(string(output))
	if isNftMissingObjectError(msg) {
		return nil
	}
	return fmt.Errorf("nft failed: %w: %s", err, msg)
}

func isNftMissingObjectError(msg string) bool {
	msg = strings.ToLower(msg)
	return strings.Contains(msg, "no such file or directory") ||
		strings.Contains(msg, "does not exist") ||
		strings.Contains(msg, "no such table") ||
		strings.Contains(msg, "no such chain")
}

func ensureNftForwardTable() error {
	if err := exec.Command("nft", "list", "table", "inet", nftForwardTable).Run(); err == nil {
		return nil
	}
	return runNftScript(fmt.Sprintf("add table inet %s\n", nftForwardTable))
}
