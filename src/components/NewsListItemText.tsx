import * as React from "react";
import { Platform, PlatformIOSStatic, StyleSheet, Text } from "react-native";

export const NewsListItemText: React.FC = ({ children }) => (
  <Text style={styles.newsListItemText}>{children}</Text>
);

const styles = StyleSheet.create({
  newsListItemText: {
    fontSize: (Platform as PlatformIOSStatic).isPad ? 30 : 25,
    fontFamily: "Helvetica Neue",
    fontWeight: "300",
    color: "white",
    textShadowColor: "rgba(0, 0, 0, 0.1)",
    textShadowRadius: 1
  }
});
