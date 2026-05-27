package handler

import "testing"

func TestBuildLocalAgentInstallCommand(t *testing.T) {
	got := buildLocalAgentInstallCommand("https://203.0.113.10:6365", "node-token")
	want := "apt update && apt install -y git curl && curl -fsSL https://get.docker.com | bash && systemctl enable --now docker && rm -rf /root/flvx_agent && git clone https://github.com/diduifei/-flaqi.git /root/flvx_agent && cd /root/flvx_agent/go-backend && docker build -t flvx-agent-local . && docker run -d --name flvx-agent --network host --restart always --privileged -v /var/run/docker.sock:/var/run/docker.sock flvx-agent-local ./flvx-agent -a 203.0.113.10:6365 -s node-token"

	if got != want {
		t.Fatalf("buildLocalAgentInstallCommand() = %q, want %q", got, want)
	}
}
