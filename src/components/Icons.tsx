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

export const ErrorIcon = (props: SvgProps) => (
  <Svg height={24} width={24} viewBox="0 0 24 24" {...props}>
    <Path
      fill={props.fill ?? "#fff"}
      d="M4.93 19.07A10 10 0 1 1 19.07 4.93 10 10 0 0 1 4.93 19.07zm1.41-1.41A8 8 0 1 0 17.66 6.34 8 8 0 0 0 6.34 17.66zM13.41 12l1.42 1.41a1 1 0 1 1-1.42 1.42L12 13.4l-1.41 1.42a1 1 0 1 1-1.42-1.42L10.6 12l-1.42-1.41a1 1 0 1 1 1.42-1.42L12 10.6l1.41-1.42a1 1 0 1 1 1.42 1.42L13.4 12z"
    />
  </Svg>
);

export const HeartIcon = (props: SvgProps) => (
  <Svg viewBox="0 0 24 24" {...props}>
    <Path d="M12 21a1 1 0 01-.71-.29l-7.77-7.78a5.26 5.26 0 010-7.4 5.24 5.24 0 017.4 0L12 6.61l1.08-1.08a5.24 5.24 0 017.4 0 5.26 5.26 0 010 7.4l-7.77 7.78A1 1 0 0112 21z" />
  </Svg>
);
