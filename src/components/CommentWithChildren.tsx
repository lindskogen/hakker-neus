import * as d3 from "d3-scale-chromatic";
import qs from "query-string";

import * as React from "react";
import { useState } from "react";
import { TouchableHighlight, View } from "react-native";
import Collapsible from "react-native-collapsible";
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
        paddingTop: padding,
        marginLeft: (padding / 2) * depth,
        minHeight: 40,
        backgroundColor: d3.interpolateBlues(0.6)
      }}
    >
      <TouchableHighlight
        underlayColor={d3.interpolateBlues(0.5)}
        onPress={() => setIsCollapsed(state => !state)}
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
          <CommentHeader isOp={isOp} comment={comment} />
        </View>
      </TouchableHighlight>
      <Collapsible collapsed={isCollapsed}>
        <TouchableHighlight
          underlayColor={d3.interpolateBlues(0.5)}
          onPress={() => setIsCollapsed(state => !state)}
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
            <HTMLComment comment={comment} onLinkPress={handlePressLink} />
          </View>
        </TouchableHighlight>

        {(comment.kids || [])
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
      </Collapsible>
    </View>
  );
};
