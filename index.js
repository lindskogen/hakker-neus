import "react-native-gesture-handler";
import { AppRegistry } from "react-native";
import App from "./App";
import { enableScreens } from "react-native-screens";
import "./src/lib/error-tracking";

enableScreens();

AppRegistry.registerComponent("HackerNeus", () => App);
