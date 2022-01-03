import Bugsnag from "@bugsnag/expo";

Bugsnag.start({
  releaseStage: "dev",
  enabledReleaseStages: ["prod", "staging"],
});
