package handler

import "testing"

func TestBuildLocalAgentInstallCommand(t *testing.T) {
	tests := []struct {
		name      string
		panelAddr string
		wantAddr  string
	}{
		{name: "ipv4 with scheme and port", panelAddr: "https://203.0.113.10:6365", wantAddr: "203.0.113.10:6365"},
		{name: "domain without port", panelAddr: "panel.example.com", wantAddr: "panel.example.com:6365"},
		{name: "ipv6 with scheme and port", panelAddr: "https://[2001:db8::10]:6365", wantAddr: "[2001:db8::10]:6365"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := buildLocalAgentInstallCommand(tt.panelAddr, "node-token")
			want := "apt update && apt install -y git curl && curl -fsSL https://get.docker.com | bash && systemctl enable --now docker && rm -rf /root/flvx_agent && git clone https://github.com/diduifei/-flaqi.git /root/flvx_agent && cd /root/flvx_agent/go-backend && docker build -t flvx-agent-local . && docker run -d --name flvx-agent --network host --restart always --privileged -v /var/run/docker.sock:/var/run/docker.sock flvx-agent-local ./flvx-agent -a " + tt.wantAddr + " -s node-token"

			if got != want {
				t.Fatalf("buildLocalAgentInstallCommand() = %q, want %q", got, want)
			}
		})
	}
}
