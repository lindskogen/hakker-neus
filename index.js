import "react-native-gesture-handler";
import { AppRegistry } from "react-native";
import App from "./App";
import { enableScreens } from "react-native-screens";

enableScreens();

AppRegistry.registerComponent("HackerNeus", () => App);
