import * as React from "react";
import { WebView } from "react-native-webview";

export const BrowserScreen = ({ navigation }) => {
  const { url } = navigation.state.params;
  return <WebView source={{ uri: url }}/>;
};
