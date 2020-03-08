import * as React from "react";
import { Share, Text, TouchableOpacity } from "react-native";
import { openURL } from "../common/browser";
import { HNStory } from "../common/types";
import { backgroundOrange, fontFamily, padding, postAuthorFontSize } from "../common/vars";
import { decodeHTMLEntities } from "../lib/formatter";
import { makeHNUrl } from "../lib/makeHNUrl";
import { NewsListItem } from "./NewsListItem";
import { NewsListItemText } from "./NewsListItemText";
import { StackNavigationProp } from "react-navigation-stack/lib/typescript/src/vendor/types";

interface CommentsListHeaderProps {
  navigation: StackNavigationProp<{}, {}>;
  story: HNStory;
}

export const CommentsListItemHeader: React.FC<CommentsListHeaderProps> = ({
  navigation,
  story: { by, id, title, url }
}) => (
  <NewsListItem backgroundColor={backgroundOrange}>
    <TouchableOpacity
      onLongPress={() => {
        Share.share({
          title: decodeHTMLEntities(title),
          url: makeHNUrl(id)
        });
      }}
      onPress={() => {
        if (url) {
          openURL(url);
        }
      }}
    >
      <NewsListItemText>{decodeHTMLEntities(title)}</NewsListItemText>
      <Text
        style={{
          fontSize: postAuthorFontSize,
          fontFamily,
          paddingTop: padding / 2,
          color: "white"
        }}
      >
        by {by.id}
      </Text>
    </TouchableOpacity>
  </NewsListItem>
);
