import * as React from "react";
import { StyleSheet, View } from "react-native";
import { padding } from "../common/vars";

export const NewsListItem: React.FC<{ backgroundColor: string }> = ({
  backgroundColor,
  children
}) => (
  <View style={[styles.newsListItemView, { backgroundColor }]}>{children}</View>
);

const styles = StyleSheet.create({
  newsListItemView: {
    padding,
    minHeight: 100,
    paddingVertical: padding * 2,
  }
});
