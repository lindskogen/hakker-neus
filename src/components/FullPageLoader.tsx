import * as React from "react";
import { ActivityIndicator } from "react-native";
import { FullPageView } from "./FullPageView";

export const Loader = () => (
  <ActivityIndicator color={"white"} size={"large"} />
);

export const FullPageLoader: React.FC<{ backgroundColor: string }> = ({
  backgroundColor
}) => (
  <FullPageView backgroundColor={backgroundColor}>
    <Loader />
  </FullPageView>
);
