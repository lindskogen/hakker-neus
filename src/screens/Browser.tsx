import * as React from "react";
import { WebView } from "react-native-webview";
import { NavigationScreenProp } from "react-navigation";

interface BrowserScreenProps {
  navigation: NavigationScreenProp<{}, { url: string }>;
}

export const BrowserScreen: React.FC<BrowserScreenProps> = ({ navigation }) => {
  const { url } = navigation.state.params!;
  return <WebView source={{ uri: url }} />;
};
