package format

import "testing"

func TestSpeedToMbps(t *testing.T) {
	tests := []struct {
		name           string
		bytesPerSecond float64
		want           string
	}{
		{name: "zero", bytesPerSecond: 0, want: "0 Kbps"},
		{name: "kilobits", bytesPerSecond: 125, want: "1.00 Kbps"},
		{name: "megabits", bytesPerSecond: 125000, want: "1.00 Mbps"},
		{name: "gigabits", bytesPerSecond: 125000000, want: "1.00 Gbps"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := SpeedToMbps(tt.bytesPerSecond); got != tt.want {
				t.Fatalf("SpeedToMbps(%v) = %q, want %q", tt.bytesPerSecond, got, tt.want)
			}
		})
	}
}
