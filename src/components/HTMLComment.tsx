import * as React from "react";
import HTMLView from "react-native-htmlview";
import { HNComment } from "../common/types";
import { fontFamily, fontFamilyMonospaced, padding } from "../common/vars";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { decodeHTMLEntities } from "../lib/formatter";

const preprocessHTML = (str: string): string => {
  if (str.indexOf("<") !== 0) {
    str = "<p>" + str;
  }
  str = str.replace(/<p><pre>/g, "<pre>");
  return str;
};

const RenderNode: React.FC = ({ children, ...props }) => {
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
    value={preprocessHTML(comment.text)}
    onLinkPress={url => onLinkPress(url)}
    NodeComponent={RenderNode}
    TextComponent={props => {
      return <Text {...props} />;
    }}
    textComponentProps={{
      style: {
        fontSize: 16,
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
          <ScrollView
            key={index}
            horizontal
            style={{
              marginVertical: padding,
              padding,
              borderStyle: "solid",
              borderWidth: StyleSheet.hairlineWidth,
              borderColor: "rgba(255,255,255,0.25)"
            }}
          >
            <View
              onStartShouldSetResponder={event => {
                console.log(event);
                return true;
              }}
              onMoveShouldSetResponder={() => true}
            >
              {defaultRenderer((node as any).children, parent)}
            </View>
          </ScrollView>
        );
      }

      let linkPressHandler = null;
      if (node.name === "a" && node.attribs && node.attribs.href) {
        linkPressHandler = () =>
          onLinkPress(decodeHTMLEntities(node.attribs.href));

        return (
          <RenderNode
            onStartShouldSetResponder={() => true}
            key={index}
            onResponderRelease={linkPressHandler}
            style={{
              color: "white",
              textDecorationLine: "underline"
            }}
          >
            {defaultRenderer(node.children, node)}
          </RenderNode>
        );
      }

      return undefined;
    }}
  />
);
