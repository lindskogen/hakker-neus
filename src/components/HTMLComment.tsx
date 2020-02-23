import * as React from "react";
import HTMLView from "react-native-htmlview";
import { HNComment } from "../common/types";
import { fontFamily, fontFamilyMonospaced, padding } from "../common/vars";
import { ScrollView, StyleSheet, Text, View } from "react-native";

const preprocessHTML = (str: string): string => {
  if (str.indexOf("<") !== 0) {
    str = "<p>" + str;
  }
  str = str.replace(/<p><pre>/g, "<pre>");
  return str;
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
    NodeComponent={({ children, ...props }) => {
      return (
        <View {...props}>
          {React.Children.map(children, ch =>
            typeof ch === "string" ? <Text>{ch}</Text> : ch
          )}
        </View>
      );
    }}
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
        color: "white"
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
              onStartShouldSetResponder={() => true}
              onMoveShouldSetResponder={() => true}
            >
              {defaultRenderer((node as any).children, parent)}
            </View>
          </ScrollView>
        );
      }

      return undefined;
    }}
  />
);
