import { Linking } from "react-native";
import InAppBrowser from "react-native-inappbrowser-reborn";
import { backgroundDark } from "./vars";

export const openURL = async (url: string) => {
  try {
    if (await InAppBrowser.isAvailable()) {
      const result = await InAppBrowser.open(url, {
        // iOS Properties
        preferredBarTintColor: backgroundDark,
        preferredControlTintColor: "white",
        dismissButtonStyle: "done",
        readerMode: false,
        animated: true,
        modalEnabled: false,
        // Android Properties
        toolbarColor: backgroundDark,
        showTitle: true,
        enableUrlBarHiding: true,
        enableDefaultShare: true,
        forceCloseOnRedirection: false,
        // Specify full animation resource identifier(package:anim/name)
        // or only resource name(in case of animation bundled with app).
        animations: {
          startEnter: "slide_in_right",
          startExit: "slide_out_left",
          endEnter: "slide_in_left",
          endExit: "slide_out_right"
        },
        waitForRedirectDelay: 0
      });

      console.log(JSON.stringify(result));
    } else {
      await Linking.openURL(url);
    }
  } catch (error) {
    console.log(error.message);
  }
};
