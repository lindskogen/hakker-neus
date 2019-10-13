import * as React from "react";
import { ActivityIndicator, View } from "react-native";

export const Loader: React.FC<{ backgroundColor: string }> = ({
  backgroundColor
}) => (
  <View
    style={{
      flex: 1,
      justifyContent: "center",
      alignItems: "center",
      backgroundColor
    }}
  >
    <ActivityIndicator color={"white"} size={"large"} />
  </View>
);
