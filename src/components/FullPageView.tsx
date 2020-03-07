import * as React from "react";
import { View } from "react-native";

export const FullPageView: React.FC<{ backgroundColor: string }> = ({
  backgroundColor,
  children
}) => (
  <View
    style={{
      flex: 1,
      justifyContent: "center",
      alignItems: "center",
      backgroundColor
    }}
  >
    {children}
  </View>
);
