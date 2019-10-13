import * as d3 from "d3-scale-chromatic";
import qs from "query-string";

import * as React from "react";
import { useState } from "react";
import { TouchableOpacity, View } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNComment } from "../common/types";
import { padding } from "../common/vars";
import { CommentHeader } from "./CommentsHeader";
import { HTMLComment } from "./HTMLComment";

const createLinkHandler = (navigation: NavigationScreenProp<{}, {}>) => (
  href: string
) => {
  if (/^https?:\/\/news.ycombinator.com/.test(href)) {
    const parsedHref = qs.parseUrl(href);
    const { id } = parsedHref.query;
    navigation.navigate({
      routeName: "Comments",
      params: { id }
    });
  } else {
    navigation.navigate({
      routeName: "Browser",
      params: { url: href }
    });
  }
};

interface CommentProps {
  op: string;
  comment: HNComment;
  depth: number;
  navigation: NavigationScreenProp<{}, {}>;
}

export const CommentWithChildren: React.FC<CommentProps> = ({
  op,
  comment,
  depth,
  navigation
}) => {
  const [isCollapsed, setIsCollapsed] = useState(false);

  const isOp = op === comment.by.id;

  const handlePressLink = createLinkHandler(navigation);

  return (
    <View
      style={{
        marginTop: depth === 0 ? 0 : padding,
        marginLeft: (padding / 2) * depth,
        minHeight: 40,
        backgroundColor: d3.interpolateBlues(0.6)
      }}
    >
      <View
        style={{
          padding,
          paddingVertical: padding / 2,
          borderLeftColor:
            depth === 0 ? "transparent" : d3.schemeTableau10[depth],
          borderLeftWidth: 5
        }}
      >
        <TouchableOpacity onPress={() => setIsCollapsed(state => !state)}>
          <CommentHeader isOp={isOp} comment={comment} />
        </TouchableOpacity>
        {!isCollapsed && (
          <HTMLComment comment={comment} onLinkPress={handlePressLink} />
        )}
      </View>
      {!isCollapsed &&
        (comment.kids || [])
          .filter(kid => !!kid.text)
          .map(kid => (
            <CommentWithChildren
              op={op}
              key={kid.id}
              comment={kid}
              depth={depth + 1}
              navigation={navigation}
            />
          ))}
    </View>
  );
};
