import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { Share, TouchableOpacity } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { CommentText } from "./CommentText";
import { NewsListItem } from "./NewsListItem";
import { NewsListItemText } from "./NewsListItemText";

interface CommentsListHeaderProps {
  navigation: NavigationScreenProp<{}, {}>;
  story: { id: string; by: { id: string }; title: string; url: string };
}

export const CommentsListItemHeader: React.FC<CommentsListHeaderProps> = ({
  navigation,
  story: { by, id, title, url }
}) => (
  <NewsListItem backgroundColor={d3.interpolateOranges(0.65)}>
    <TouchableOpacity
      style={{ flex: 1 }}
      onLongPress={() => {
        Share.share({
          title: title,
          url: "https://news.ycombinator.com/item?id=" + id
        });
      }}
      onPress={() => {
        navigation.navigate({
          routeName: "Browser",
          params: { url: url }
        });
      }}
    >
      <NewsListItemText>{title}</NewsListItemText>
      <CommentText>by {by.id}</CommentText>
    </TouchableOpacity>
  </NewsListItem>
);
