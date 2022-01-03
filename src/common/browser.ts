import { Linking } from "react-native";
import * as WebBrowser from "expo-web-browser";
import { backgroundDark } from "./vars";

export const openURL = async (url: string) => {
  try {
    const result = await WebBrowser.openBrowserAsync(url, {
      // Common props
      toolbarColor: backgroundDark,

      // iOS Properties
      controlsColor: "white",
      dismissButtonStyle: "done",
      readerMode: false,

      // Android Properties
      secondaryToolbarColor: backgroundDark,
      showTitle: true,
      enableDefaultShareMenuItem: true,
    });

    if (result.type !== "cancel") {
      console.log(JSON.stringify(result));
    }
  } catch (error) {
    console.log(error.message);
    await Linking.openURL(url);
  }
};
