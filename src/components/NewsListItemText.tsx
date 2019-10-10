import * as React from "react";
import { Platform, PlatformIOSStatic, Text } from "react-native";

export const NewsListItemText = ({ children }) => (
  <Text
    style={{
      fontSize: (Platform as PlatformIOSStatic).isPad ? 30 : 25,
      fontFamily: "Helvetica Neue",
      fontWeight: "300",
      color: "white",
      textShadowColor: "rgba(0, 0, 0, 0.1)",
      textShadowRadius: 1
    }}
  >
    {children}
  </Text>
);
