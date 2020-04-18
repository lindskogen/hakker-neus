import qs from "query-string";

import * as React from "react";
import { Share, StyleSheet, TouchableHighlight, View } from "react-native";
import { openURL } from "../common/browser";
import { HNComment } from "../common/types";
import { backgroundDark, padding } from "../common/vars";
import { makeHNUrl } from "../lib/makeHNUrl";
import { CommentHeader } from "./CommentsHeader";
import { HTMLComment } from "./HTMLComment";
import { ContainerWithLeftBorder } from "./ContainerWithLeftBorder";
import { StackNavigationProp } from "@react-navigation/stack";
import { RootStackParamList } from "../../App";
import { useAppNavigation } from "../common/useAppNavigation";
import { isHackerNewsUrl } from "../lib/isHackerNewsUrl";

const createLinkHandler = (
  navigation: StackNavigationProp<RootStackParamList>
) => (href: string) => {
  if (isHackerNewsUrl(href)) {
    const parsedHref = qs.parseUrl(href);
    const { id } = parsedHref.query;
    if (id && !Array.isArray(id)) {
      navigation.push("Comments", { id });
    }
  } else {
    openURL(href);
  }
};

interface CommentProps {
  op: string;
  comment: HNComment;
  depth: number;
}

export const CommentWithChildren: React.FC<CommentProps> = ({
  op,
  comment,
  depth
}) => {
  const isOp = op === comment.by?.id;
  const navigation = useAppNavigation();

  const handlePressLink = createLinkHandler(navigation);

  const handleLongPress = () => {
    Share.share({
      url: makeHNUrl(String(comment.id))
    });
  };

  return (
    <View
      style={{
        paddingVertical: padding,
        marginLeft: padding * depth,
        minHeight: 40,
        backgroundColor: backgroundDark,
        borderTopColor: "#fff3",
        borderTopWidth: StyleSheet.hairlineWidth
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
