import * as React from "react";
import Svg, { Path, SvgProps } from "react-native-svg";

export const EmptyStateIcon = (props: SvgProps) => (
  <Svg height={24} width={24} viewBox="0 0 24 24" {...props}>
    <Path
      fill="#fff"
      d="M2 15V5c0-1.1.9-2 2-2h16a2 2 0 0 1 2 2v15a1 1 0 0 1-1.7.7L16.58 17H4a2 2 0 0 1-2-2zM20 5H4v10h13a1 1 0 0 1 .7.3l2.3 2.29V5z"
    />
  </Svg>
);
