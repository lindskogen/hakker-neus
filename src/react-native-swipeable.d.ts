declare module "react-native-swipeable" {
  import { ReactNode } from "react";

  interface Props {
    rightContent: ReactNode;
    onRightActionRelease?: () => void;
  }

  export default class Swipable extends React.Component<Props> {}
}
