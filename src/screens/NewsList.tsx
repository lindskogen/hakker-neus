import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import * as React from "react";
import {
  FlatList,
  RefreshControl,
  Share,
  StyleSheet,
  Text,
  TouchableOpacity,
  View
} from "react-native";
import Swipeable from "react-native-swipeable";
import { NavigationScreenProp } from "react-navigation";
import { useQuery } from "urql";
import { Loader } from "../components/Loader";
import { NewsListItem } from "../components/NewsListItem";
import { NewsListItemText } from "../components/NewsListItemText";

interface NewsListProps {
  navigation: NavigationScreenProp<{}, {}>;
}

export const NewsList: React.FC<NewsListProps> = ({ navigation }) => {
  const [{ data, fetching }, executeQuery] = useQuery({
    query: gql`
      query Query {
        hn {
          topStories {
            id
            descendants
            type
            title
            by {
              id
            }
            text
            url
            score
          }
        }
      }
    `
  });

  if (!data) {
    return <Loader backgroundColor={d3.interpolateOranges(0.65)} />;
  }

  const stories = data.hn.topStories;

  return (
    <FlatList
      style={{ backgroundColor: "black" }}
      data={stories}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => executeQuery({ requestPolicy: "network-only" })}
          tintColor={"white"}
        />
      }
      keyExtractor={item => item.id}
      renderItem={({ item: story, index }) => (
        <Swipeable
          rightContent={
            <View
              style={{
                backgroundColor: "#000",
                flex: 1,
                justifyContent: "center",
                alignItems: "flex-start",
                paddingLeft: 20
              }}
            >
              <Text
                style={{
                  fontSize: 50,
                  fontFamily: "Helvetica Neue",
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
          onRightActionRelease={() =>
            navigation.navigate({
              routeName: "Comments",
              params: { id: story.id, story }
            })
          }
          key={story.id}
        >
          <NewsListItem
            backgroundColor={d3.interpolateOranges(
              (index / stories.length) * 0.35 + 0.65
            )}
          >
            <TouchableOpacity
              style={{ flex: 1 }}
              onLongPress={() => {
                Share.share({ title: story.title, url: story.url });
              }}
              onPress={() => {
                navigation.navigate({
                  routeName: "Browser",
                  params: { url: story.url }
                });
              }}
            >
              <NewsListItemText>{story.title}</NewsListItemText>
            </TouchableOpacity>
            <Text style={styles.scoreText}>{story.score}</Text>
          </NewsListItem>
        </Swipeable>
      )}
    />
  );
};

const styles = StyleSheet.create({
  scoreText: {
    position: "absolute",
    right: 20,
    bottom: 20,
    fontSize: 50,
    fontFamily: "Helvetica Neue",
    color: "white",
    opacity: 0.3,
    textShadowColor: "rgba(0, 0, 0, 0.1)",
    textShadowOffset: { height: 0, width: 0 },
    textShadowRadius: 1
  }
});
