import * as React from "react";
import { useEffect } from "react";
import { Linking } from "react-native";
import InAppBrowser from "react-native-inappbrowser-reborn";
import { NavigationScreenProp } from "react-navigation";
import { backgroundDark } from "../common/vars";

interface BrowserScreenProps {
  navigation: NavigationScreenProp<{}, { url: string }>;
}

export const BrowserScreen: React.FC<BrowserScreenProps> = ({ navigation }) => {
  const { url } = navigation.state.params!;

  useEffect(() => {


    fn();
  }, [url]);

  return null;
};
