import * as React from "react";
import { Platform, ScrollView, Text, View } from "react-native";
import HTML from "react-native-render-html";
import { HNComment } from "../common/types";
import { fontFamily, fontFamilyMonospaced, padding } from "../common/vars";

export const HTMLComment = ({
  comment,
  onLinkPress
}: {
  comment: HNComment;
  onLinkPress: (href: string) => void;
}) => (
  <HTML
    html={comment.text}
    onLinkPress={(event, href) => onLinkPress(href)}
    baseFontStyle={{
      fontSize: 16,
      fontFamily,
      color: "white"
    }}
    tagsStyles={{
      a: {
        color: "white"
      },
      code: {
        fontFamily: fontFamilyMonospaced
      }
    }}
    renderers={{
      p: (htmlAttribs, children, convertedCSSStyles, passProps) => (
        <View key={passProps.key} style={{ marginVertical: padding }}>
          {children}
        </View>
      ),
      pre: (htmlAttribs, children, convertedCSSStyles, passProps) => (
        <ScrollView
          key={passProps.key}
          style={{ marginVertical: padding }}
          horizontal={true}
        >
          {passProps.rawChildren[0].tagName === "code" ? (
            <Text
              style={{
                ...passProps.baseFontStyle,
                ...passProps.tagsStyles.code
              }}
            >
              {passProps.rawChildren[0].parent!.children[0].children[0].data}
            </Text>
          ) : (
            children
          )}
        </ScrollView>
      )
    }}
  />
);
