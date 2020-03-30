import "react-native-gesture-handler";
import { AppRegistry } from "react-native";
import App from "./App";
import { enableScreens } from "react-native-screens";
import "./src/lib/error-tracking";

require('react-native').unstable_enableLogBox()

enableScreens();

AppRegistry.registerComponent("HackerNeus", () => App);
