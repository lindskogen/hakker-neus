import * as React from "react";
import { StyleSheet, View } from "react-native";
import { padding } from "../common/vars";

export const NewsListItem: React.FC<{ backgroundColor: string }> = ({
  backgroundColor,
  children
}) => (
  <View
    style={{
      padding,
      minHeight: 100,
      borderBottomColor: "#000",
      borderBottomWidth: StyleSheet.hairlineWidth,
      backgroundColor
    }}
  >
    {children}
  </View>
);
