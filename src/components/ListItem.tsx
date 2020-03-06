import * as React from "react";
import { HNStory } from "../common/types";
import { NavigationScreenProp } from "react-navigation";
import Swipeable from "react-native-swipeable";
import { Share, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { backgroundDark, fontFamily } from "../common/vars";
import { NewsListItem } from "./NewsListItem";
import { decodeHTMLEntities } from "../lib/formatter";
import { makeHNUrl } from "../lib/makeHNUrl";
import { openURL } from "../common/browser";
import { NewsListItemText } from "./NewsListItemText";
import { fetchCommentsForItem } from "../fetchers/fetchCommentsForItem";
// @ts-ignore
import { queryCache } from "react-query";

export const ListItem: React.FC<{
  story: HNStory;
  navigation: NavigationScreenProp<{}, {}>;
  backgroundColor: string;
}> = ({ navigation, backgroundColor, story }) => (
  <Swipeable
    rightContent={
      <View
        style={{
          backgroundColor: backgroundDark,
          flex: 1,
          justifyContent: "center",
          alignItems: "flex-start",
          paddingLeft: 20
        }}
      >
        <Text
          style={{
            fontSize: 50,
            fontFamily,
            color: "white",
            textShadowColor: "rgba(0, 0, 0, 0.1)",
            textShadowOffset: { height: 0, width: 0 },
            textShadowRadius: 1
          }}
        >
          {story.descendants}
        </Text>
      </View>
    }
    onRightActionRelease={() => {
      queryCache.prefetchQuery(
        ["comments", { id: story.id }],
        fetchCommentsForItem
      );
      navigation.navigate({
        routeName: "Comments",
        params: { id: story.id, story }
      });
    }}
  >
    <NewsListItem backgroundColor={backgroundColor}>
      <TouchableOpacity
        style={{ flex: 1 }}
        onLongPress={() => {
          Share.share({
            title: decodeHTMLEntities(story.title),
            url: story.url || makeHNUrl(story.id)
          });
        }}
        onPress={() => {
          if (story.url) {
            openURL(story.url);
          } else {
            queryCache.prefetchQuery(
              ["comments", { id: story.id }],
              fetchCommentsForItem
            );
            navigation.navigate({
              routeName: "Comments",
              params: { id: story.id, story }
            });
          }
        }}
      >
        <NewsListItemText>{decodeHTMLEntities(story.title)}</NewsListItemText>
      </TouchableOpacity>
      <Text style={styles.scoreText}>{story.score}</Text>
    </NewsListItem>
  </Swipeable>
);

const styles = StyleSheet.create({
  scoreText: {
    position: "absolute",
    right: 20,
    bottom: 20,
    fontSize: 50,
    fontFamily,
    color: "white",
    opacity: 0.3,
    textShadowColor: "rgba(0, 0, 0, 0.1)",
    textShadowOffset: { height: 0, width: 0 },
    textShadowRadius: 1
  }
});
