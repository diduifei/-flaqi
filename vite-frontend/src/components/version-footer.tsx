import { useEffect, useState } from "react";

import { siteConfig } from "@/config/site";
import {
  UPDATE_CHANNEL_CHANGED_EVENT,
  type UpdateReleaseChannel,
  getLatestVersionByChannel,
  getUpdateReleaseChannel,
  hasVersionUpdate,
} from "@/utils/version-update";

const FALLBACK_GITHUB_REPO = "https://github.com/Sagit-chu/flux-panel";

interface VersionFooterProps {
  version: string;
  containerClassName?: string;
  versionClassName?: string;
  poweredClassName?: string;
  updateBadgeClassName?: string;
}

export function VersionFooter({
  version,
  containerClassName,
  versionClassName,
  poweredClassName,
  updateBadgeClassName,
}: VersionFooterProps) {
  const [footerConfig, setFooterConfig] = useState({
    hidden: siteConfig.hide_footer_brand === true,
    text: (siteConfig.footer_text || "").trim(),
  });
  const [channel, setChannel] = useState<UpdateReleaseChannel>(
    getUpdateReleaseChannel(),
  );
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [latestUpdateVersion, setLatestUpdateVersion] = useState<string | null>(
    null,
  );

  useEffect(() => {
    const syncFooterConfig = () => {
      setFooterConfig({
        hidden: siteConfig.hide_footer_brand === true,
        text: (siteConfig.footer_text || "").trim(),
      });
    };

    window.addEventListener("site-config-updated", syncFooterConfig);

    return () => {
      window.removeEventListener("site-config-updated", syncFooterConfig);
    };
  }, []);

  useEffect(() => {
    const handleChannelChange = () => {
      setChannel(getUpdateReleaseChannel());
    };

    window.addEventListener(UPDATE_CHANNEL_CHANGED_EVENT, handleChannelChange);
    window.addEventListener("storage", handleChannelChange);

    return () => {
      window.removeEventListener(
        UPDATE_CHANNEL_CHANGED_EVENT,
        handleChannelChange,
      );
      window.removeEventListener("storage", handleChannelChange);
    };
  }, []);

  useEffect(() => {
    let active = true;

    const checkUpdate = async () => {
      const latestVersion = await getLatestVersionByChannel(
        channel,
        siteConfig.github_repo || FALLBACK_GITHUB_REPO,
      );

      if (!active) {
        return;
      }

      if (!latestVersion) {
        setUpdateAvailable(false);
        setLatestUpdateVersion(null);

        return;
      }

      const hasUpdate = hasVersionUpdate(version, latestVersion);

      setUpdateAvailable(hasUpdate);
      setLatestUpdateVersion(hasUpdate ? latestVersion : null);
    };

    void checkUpdate();

    return () => {
      active = false;
    };
  }, [channel, version]);

  const shouldShowFooterText =
    !footerConfig.hidden && footerConfig.text.length > 0;

  return (
    <div className={containerClassName}>
      <p className={versionClassName}>
        v{version}
        {updateAvailable && latestUpdateVersion && (
          <span className={updateBadgeClassName} role="status">
            {latestUpdateVersion}
          </span>
        )}
      </p>
      {shouldShowFooterText && (
        <p className={poweredClassName}>{footerConfig.text}</p>
      )}
    </div>
  );
}
