import qs from "query-string";

import * as React from "react";
import { Share, TouchableHighlight, View } from "react-native";
import { openURL } from "../common/browser";
import { HNComment } from "../common/types";
import { backgroundDark, padding } from "../common/vars";
import { makeHNUrl } from "../lib/makeHNUrl";
import { CommentHeader } from "./CommentsHeader";
import { HTMLComment } from "./HTMLComment";
import { ContainerWithLeftBorder } from "./ContainerWithLeftBorder";
import { StackNavigationProp } from "react-navigation-stack/lib/typescript/src/vendor/types";

const createLinkHandler = (navigation: StackNavigationProp<{}, {}>) => (
  href: string
) => {
  if (/^https?:\/\/news.ycombinator.com/.test(href)) {
    const parsedHref = qs.parseUrl(href);
    const { id } = parsedHref.query;
    navigation.push("Comments", { id });
  } else {
    openURL(href);
  }
};

interface CommentProps {
  op: string;
  comment: HNComment;
  depth: number;
  navigation: StackNavigationProp<{}, {}>;
}

export const CommentWithChildren: React.FC<CommentProps> = ({
  op,
  comment,
  depth,
  navigation
}) => {
  const isOp = op === comment.by.id;

  const handlePressLink = createLinkHandler(navigation);

  const handleLongPress = () => {
    Share.share({
      url: makeHNUrl(String(comment.id))
    });
  };

  return (
    <View
      style={{
        marginTop: depth === 0 ? 0 : padding,
        paddingTop: padding,
        marginLeft: (padding / 2) * depth,
        minHeight: 40,
        backgroundColor: backgroundDark
      }}
    >
      <TouchableHighlight
        underlayColor={backgroundDark}
        onLongPress={handleLongPress}
      >
        <ContainerWithLeftBorder depth={depth}>
          <CommentHeader isOp={isOp} comment={comment} />
          <HTMLComment comment={comment} onLinkPress={handlePressLink} />
        </ContainerWithLeftBorder>
      </TouchableHighlight>
    </View>
  );
};
