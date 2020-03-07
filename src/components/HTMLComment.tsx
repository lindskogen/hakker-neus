import * as React from "react";
import HTMLView from "react-native-htmlview";
import { HNComment } from "../common/types";
import { fontFamily, fontFamilyMonospaced, padding, postAuthorFontSize } from "../common/vars";
import { ScrollView, StyleSheet, Text, View, ViewProps } from "react-native";
import { decodeHTMLEntities } from "../lib/formatter";

const preprocessHTML = (str: string): string => {
  if (str.indexOf("<") !== 0) {
    str = "<p>" + str;
  }
  str = str.replace(/<p><pre>/g, "<pre>");
  return str;
};

const CommentNode: React.FC<ViewProps> = ({ children, ...props }) => {
  return (
    <View {...props}>
      {React.Children.map(children, ch =>
        typeof ch === "string" ? <Text>{ch}</Text> : ch
      )}
    </View>
  );
};

export const HTMLComment = ({
  comment,
  onLinkPress
}: {
  comment: HNComment;
  onLinkPress: (href: string) => void;
}) => (
  <HTMLView
    value={preprocessHTML(comment.text ?? "")}
    onLinkPress={onLinkPress}
    NodeComponent={CommentNode}
    textComponentProps={{
      style: {
        fontSize: postAuthorFontSize,
        fontFamily,
        color: "white"
      }
    }}
    stylesheet={{
      a: {
        color: "white",
        textDecorationLine: "underline"
      },
      code: {
        padding,
        fontSize: 14,
        fontFamily: fontFamilyMonospaced
      }
    }}
    renderNode={(node, index, siblings, parent, defaultRenderer) => {
      if (parent && parent.name === "code") {
        if (node.data) {
          node.data = node.data.replace(/^ {4}/gm, "");
        }
      }
      if (node.name === "pre") {
        return (
          <ScrollView key={index} horizontal style={{
            paddingTop: padding,
            marginVertical: padding,
            borderStyle: "solid",
            borderWidth: StyleSheet.hairlineWidth,
            borderColor: "rgba(255,255,255,0.25)",
          }}>
            <View
              onStartShouldSetResponder={() => true}
              onMoveShouldSetResponder={() => true}
            >
              {defaultRenderer((node as any).children, parent)}
            </View>
          </ScrollView>
        );
      }

      if (node.name === "a" && node.attribs && node.attribs.href) {
        return (
          <CommentNode
            onStartShouldSetResponder={() => true}
            key={index}
            onResponderRelease={() =>
              onLinkPress(decodeHTMLEntities(node.attribs.href))
            }
          >
            {defaultRenderer((node as any).children, node)}
          </CommentNode>
        );
      }

      return undefined;
    }}
  />
);
