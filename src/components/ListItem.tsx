import * as React from "react";
import { useEffect, useRef } from "react";
import { HNStory } from "../common/types";
import Swipeable from "react-native-gesture-handler/Swipeable";
import {
  Animated,
  Platform,
  PlatformIOSStatic,
  Share,
  StyleSheet,
  Text,
  TouchableOpacity,
  View
} from "react-native";
import {
  backgroundDark,
  fontFamily,
  fontWeight,
  padding
} from "../common/vars";
import { NewsListItem } from "./NewsListItem";
import { decodeHTMLEntities } from "../lib/formatter";
import { makeHNUrl } from "../lib/makeHNUrl";
import { openURL } from "../common/browser";
import { fetchCommentsForItem } from "../fetchers/fetchCommentsForItem";
import { queryCache } from "react-query";
import { useAppNavigation } from "../common/useAppNavigation";
import { useSaveStory } from "../common/useSaveStory";
import { HeartIcon } from "./Icons";

const ICON_SIZE = 48;
const LEFT_THRESHOLD = 80;
const RIGHT_THRESHOLD = 100;

export const ListItem: React.FC<{
  story: HNStory;
  backgroundColor: string;
}> = ({ backgroundColor, story }) => {
  const ref = useRef<Swipeable>(null);
  const navigation = useAppNavigation();
  const { saved, save, remove } = useSaveStory(story);
  const saveAnimation = useRef(new Animated.Value(saved ? 1 : 0)).current;

  useEffect(() => {
    Animated.spring(saveAnimation, {
      useNativeDriver: true,
      delay: 500,
      toValue: saved ? 1 : 0
    }).start();
  }, [saved]);

  const navigateToStory = () => {
    queryCache.prefetchQuery(["comments", story.id], fetchCommentsForItem);
    navigation.navigate("Comments", {
      id: story.id,
      story
    });
  };

  return (
    <Swipeable
      ref={ref}
      overshootFriction={8}
      rightThreshold={RIGHT_THRESHOLD}
      leftThreshold={LEFT_THRESHOLD}
      overshootLeft={false}
      overshootRight={false}
      renderRightActions={(progress, dragX) => {
        const scale = dragX.interpolate({
          inputRange: [-80, 0],
          outputRange: [1, 0],
          extrapolate: "clamp"
        });

        return (
          <View style={styles.commentCountBg}>
            <Animated.Text
              style={[
                {
                  fontSize: 50,
                  fontFamily,
                  color: "white",
                  textShadowColor: "rgba(0, 0, 0, 0.1)",
                  textShadowOffset: { height: 0, width: 0 },
                  textShadowRadius: 1,
                  transform: [{ scale }]
                }
              ]}
            >
              {story.descendants}
            </Animated.Text>
          </View>
        );
      }}
      onSwipeableRightWillOpen={() => {
        ref.current?.close();
        navigateToStory();
      }}
      renderLeftActions={(progress, dragX) => {
        const translateX = dragX.interpolate({
          inputRange: [0, LEFT_THRESHOLD],
          outputRange: [-LEFT_THRESHOLD, 0],
          extrapolate: "clamp"
        });

        const opacity = dragX.interpolate({
          inputRange: [0, 10, LEFT_THRESHOLD],
          outputRange: [0, 0, 1],
          extrapolate: "clamp"
        });

        return (
          <View style={styles.saveBg}>
            <Animated.View style={{ opacity, transform: [{ translateX }] }}>
              <HeartIcon
                fill={"#fff"}
                stroke={"#fff"}
                width={ICON_SIZE}
                height={ICON_SIZE}
              />
            </Animated.View>
          </View>
        );
      }}
      onSwipeableLeftWillOpen={() => {
        if (saved) {
          remove();
        } else {
          save();
        }
        setTimeout(() => {
          ref.current?.close();
        }, 100);
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
              navigateToStory();
            }
          }}
        >
          <Text style={styles.newsListItemText}>
            {decodeHTMLEntities(story.title)}
          </Text>
        </TouchableOpacity>
        <Animated.View
          style={{
            position: "absolute",
            right: 10,
            top: 10,
            opacity: saveAnimation.interpolate({
              inputRange: [0, 1],
              outputRange: [0, 0.3]
            })
          }}
        >
          <HeartIcon fill={"#fff"} stroke={"#fff"} width={32} height={32} />
        </Animated.View>
        <View style={styles.scoreTextBgContainer}>
          <Text style={styles.scoreText}>{story.score}</Text>
        </View>
      </NewsListItem>
    </Swipeable>
  );
};

const styles = StyleSheet.create({
  commentCountBg: {
    backgroundColor: backgroundDark,
    justifyContent: "center",
    alignItems: "flex-end",
    paddingHorizontal: 20
  },
  saveBg: {
    backgroundColor: backgroundDark,
    width: LEFT_THRESHOLD,
    justifyContent: "center",
    alignItems: "flex-start",
    paddingLeft: 20
  },
  scoreTextBgContainer: {
    position: "absolute",
    right: padding,
    justifyContent: "center",
    bottom: padding
  },
  scoreText: {
    fontSize: 30,
    fontFamily,
    color: "white",
    opacity: 0.3,
    textShadowColor: "rgba(0, 0, 0, 0.1)",
    textShadowOffset: { height: 0, width: 0 },
    textShadowRadius: 1
  },
  newsListItemText: {
    fontSize: (Platform as PlatformIOSStatic).isPad ? 30 : 25,
    fontFamily,
    fontWeight,
    paddingRight: padding * 2,
    color: "white",
    textShadowColor: "rgba(0, 0, 0, 0.1)",
    textShadowRadius: 1
  }
});
