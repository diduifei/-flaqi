package format

import "fmt"

func SpeedToMbps(bytesPerSecond float64) string {
	if bytesPerSecond <= 0 {
		return "0 Kbps"
	}

	kbps := bytesPerSecond * 8 / 1000
	if kbps < 1000 {
		return fmt.Sprintf("%.2f Kbps", kbps)
	}

	mbps := kbps / 1000
	if mbps < 1000 {
		return fmt.Sprintf("%.2f Mbps", mbps)
	}

	return fmt.Sprintf("%.2f Gbps", mbps/1000)
}
