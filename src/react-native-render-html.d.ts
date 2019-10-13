declare module "react-native-render-html" {
  import { ViewStyle, NativeTouchEvent } from "react-native";

  type WrapperType = "Text" | "View";

  interface ParentType {
    attribs: {};
    data?: string;
    children: ParentType[];
    nodeIndex: number;
    parent: ParentType | null;
    next: ParentType | null;
    prev: ParentType | null;
    name: string;
    type: string;
    wrapper: WrapperType;
  }

  interface ChildType {
    attribs: {};
    children: ParentType[];
    nodeIndex: number;
    parent: ParentType | null;
    parentTag: string;
    parentTag: string;
    tagName: string;

    wrapper: WrapperType;
  }

  interface PassProps {
    allowFontScaling: boolean;
    baseFontStyle: {};
    classesStyles: {};
    data?: {};
    debug: boolean;
    decodeEntities: boolean;
    emSize: number;
    html: string;
    ignoredStyles: string[];
    ignoredTags: string[];
    imagesMaxWidth: number;
    key: string;
    nodeIndex: number;
    parentIndex: number;
    parentTag: string;
    parentWrapper: WrapperType;
    ptSize: number;
    rawChildren: ChildType[];
    renderers: {};
    staticContentMaxWidth: number;
    tagsStyles: {};
    textSelectable: boolean;
  }

  type CustomRenderer = (
    htmlAttribs: {},
    children: React.ReactNode,
    convertedCSSStyles: {},
    passProps: PassProps
  ) => React.ReactNode;

  interface Props {
    renderers?: {
      [key: string]:
        | CustomRenderer
        | { renderer: CustomRenderer; wrapper: WrapperType };
    };
    renderersProps?: any;
    html: string;
    uri?: string;
    decodeEntities?: boolean;
    imagesMaxWidth?: any;
    staticContentMaxWidth?: any;
    imagesInitialDimensions?: any;
    onLinkPress?: (evt: NativeTouchEvent, href: string, htmlAttribs: {}) => void;
    onParsed?: any;
    tagsStyles?: any;
    classesStyles?: any;
    listsPrefixesRenderers?: any;
    containerStyle?: ViewStyle;
    customWrapper?: any;
    remoteLoadingView?: any;
    remoteErrorView?: any;
    emSize?: any;
    ptSize?: any;
    baseFontStyle?: any;
    allowFontScaling?: any;
    textSelectable?: any;
    alterData?: any;
    alterChildren?: any;
    alterNode?: any;
    ignoredTags?: any;
    allowedStyles?: any;
    ignoredStyles?: any;
    ignoreNodesFunction?: any;
    debug?: boolean;
  }

  export default class HTML extends React.Component<Props> {}
}
