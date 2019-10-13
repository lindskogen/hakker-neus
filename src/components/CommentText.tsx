import * as React from "react";
import { Text } from "react-native";

export const CommentText: React.FC = ({ children }) => (
  <Text
    style={{
      fontSize: 16,
      fontFamily: "Helvetica Neue",
      color: "white"
    }}
  >
    {children}
  </Text>
);
