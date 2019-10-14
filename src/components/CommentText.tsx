import * as React from "react";
import { Text } from "react-native";
import { fontFamily } from "../common/vars";

export const CommentText: React.FC = ({ children }) => (
  <Text
    style={{
      fontSize: 16,
      fontFamily,
      color: "white"
    }}
  >
    {children}
  </Text>
);
