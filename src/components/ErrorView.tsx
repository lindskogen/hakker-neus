import { ErrorIcon } from "./Icons";
import { Text } from "react-native";
import { backgroundRed, fontFamily } from "../common/vars";
import * as React from "react";

export const ErrorView: React.FC<{ error: Error }> = ({ error }) => (
  <>
    <ErrorIcon width={70} height={70} opacity={0.5} fill={backgroundRed} />
    <Text
      style={{
        fontFamily,
        color: "rgba(255, 255, 255, 0.3)",
        fontWeight: "300",
        fontSize: 24
      }}
    >
      {error.name}: {error.message}
    </Text>
  </>
);
