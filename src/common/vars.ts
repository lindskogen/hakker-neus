import * as d3 from "d3-scale-chromatic";
import { Platform } from "react-native";

export const padding = 10;
export const backgroundDark = "#1b1d21";
export const backgroundRed = "#ce5b4c";
export const backgroundOrange = d3.interpolateOranges(0.65);

export const fontFamily = Platform.select({
  android: "sans-serif",
  ios: "Helvetica Neue",
  default: "sans-serif"
});
export const fontWeight = Platform.select({
  android: "100" as "100",
  ios: "300" as "300",
  default: "300" as "300"
});

export const fontFamilyMonospaced = Platform.select({
  android: "monospace",
  ios: "Menlo",
  default: "monospace"
});
