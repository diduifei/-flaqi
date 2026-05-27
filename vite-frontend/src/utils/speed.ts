export const formatSpeedToMbps = (bytesPerSecond: number): string => {
  if (!Number.isFinite(bytesPerSecond) || bytesPerSecond <= 0) {
    return "0 Kbps";
  }

  const bitsPerSecond = bytesPerSecond * 8;
  const kbps = bitsPerSecond / 1000;

  if (kbps < 1000) {
    return `${formatSpeedNumber(kbps)} Kbps`;
  }

  const mbps = kbps / 1000;

  if (mbps < 1000) {
    return `${formatSpeedNumber(mbps)} Mbps`;
  }

  return `${formatSpeedNumber(mbps / 1000)} Gbps`;
};

export const formatMegaBytesToMbps = (megaBytesPerSecond: number): string =>
  formatSpeedToMbps(megaBytesPerSecond * 1024 * 1024);

const formatSpeedNumber = (value: number): string => {
  if (!Number.isFinite(value) || value <= 0) {
    return "0";
  }

  return value.toFixed(2);
};
