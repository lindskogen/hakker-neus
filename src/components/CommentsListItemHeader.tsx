import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { Share, TouchableOpacity } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNStory } from "../common/types";
import { backgroundOrange } from "../common/vars";
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
          title,
          url: makeHNUrl(id)
        });
      }}
      onPress={() => {
        navigation.navigate({
          routeName: "Browser",
          params: { url }
        });
      }}
    >
      <NewsListItemText>{title}</NewsListItemText>
      <CommentText>by {by.id}</CommentText>
    </TouchableOpacity>
  </NewsListItem>
);
