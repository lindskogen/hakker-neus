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

export const DocumentAdd = (props: SvgProps) => (
  <Svg
    height={24}
    width={24}
    viewBox="0 0 24 24"
    fill="none"
    strokeLinecap="round"
    strokeLinejoin="round"
    strokeWidth="2"
    stroke={props.fill ?? "#fff"}
    {...props}
  >
    <Path d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
  </Svg>
);

export const DocumentRemove = (props: SvgProps) => (
  <Svg
    height={24}
    width={24}
    viewBox="0 0 24 24"
    fill="none"
    strokeLinecap="round"
    strokeLinejoin="round"
    strokeWidth="2"
    stroke={props.fill ?? "#fff"}
    {...props}
  >
    <Path d="M9 13h6m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
  </Svg>
);
