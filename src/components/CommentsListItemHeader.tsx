import * as React from "react";
import { Share, TouchableOpacity } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { openURL } from "../common/browser";
import { HNStory } from "../common/types";
import { backgroundOrange } from "../common/vars";
import { decodeHTMLEntities } from "../lib/formatter";
import { makeHNUrl } from "../lib/makeHNUrl";
import { CommentText } from "./CommentText";
import { NewsListItem } from "./NewsListItem";
import { NewsListItemText } from "./NewsListItemText";

interface CommentsListHeaderProps {
  navigation: NavigationScreenProp<{}, {}>;
  story: HNStory;
}

export const CommentsListItemHeader: React.FC<CommentsListHeaderProps> = ({
  navigation,
  story: { by, id, title, url }
}) => (
  <NewsListItem backgroundColor={backgroundOrange}>
    <TouchableOpacity
      style={{ flex: 1 }}
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
      <CommentText>by {by.id}</CommentText>
    </TouchableOpacity>
  </NewsListItem>
);
