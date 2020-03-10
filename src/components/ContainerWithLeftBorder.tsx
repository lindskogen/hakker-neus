import * as React from "react";
import { View } from "react-native";
import { padding } from "../common/vars";
import * as d3 from "d3-scale-chromatic";

interface ContainerWithLeftBorderProps {
  depth: number;
}

export const ContainerWithLeftBorder: React.FC<ContainerWithLeftBorderProps> = ({
  children,
  depth
}) => (
  <View
    style={{
      padding,
      paddingVertical: padding / 2,
      borderLeftColor: depth === 0 ? "transparent" : (d3 as any).schemeTableau10[depth],
      borderLeftWidth: 3
    }}
  >
    {children}
  </View>
);
