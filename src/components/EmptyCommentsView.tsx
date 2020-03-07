import { EmptyStateIcon } from "./EmptyStateIcon";
import { Text } from "react-native";
import { fontFamily } from "../common/vars";
import * as React from "react";

export const EmptyCommentsView = () => (
  <>
    <EmptyStateIcon width={70} height={70} opacity={0.3} />
    <Text
      style={{
        fontFamily,
        color: "rgba(255, 255, 255, 0.3)",
        fontWeight: "300",
        fontSize: 24
      }}
    >
      No comments here
    </Text>
  </>
);
