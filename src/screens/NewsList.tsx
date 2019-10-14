import * as d3 from "d3-scale-chromatic";
import gql from "graphql-tag";
import { uniqBy } from "lodash-es";
import * as React from "react";
import { memo, useEffect, useReducer } from "react";
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
import { backgroundDark, padding } from "../common/vars";
import { Loader } from "../components/Loader";
import { NewsListItem } from "../components/NewsListItem";
import { NewsListItemText } from "../components/NewsListItemText";
import { makeHNUrl } from "../lib/makeHNUrl";
import { urqlClient } from "../lib/urql";

interface NewsListProps {
  navigation: NavigationScreenProp<{}, {}>;
}

const newsListQuery = gql`
  query Query($limit: Int!, $offset: Int!) {
    hn {
      topStories(limit: $limit, offset: $offset) {
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
`;

type State = {
  data: any[];
  error: Error | null;
  offset: number;
  limit: number;
  fetching: boolean;
  fetchingMore: boolean;
};

type FetchingActions =
  | {
      type: "error";
      error: Error;
    }
  | {
      type: "start_fetch";
    }
  | {
      type: "start_fetch_more";
    }
  | {
      type: "fetch";
      data: any;
    }
  | {
      type: "fetch_more";
      data: any;
    };

const useNewsListQuery = () => {
  const [state, dispatch] = useReducer(
    (state: State, action: FetchingActions) => {
      switch (action.type) {
        case "error":
          return {
            ...state,
            fetching: false,
            fetchingMore: false,
            error: action.error
          };
        case "start_fetch":
          return {
            ...state,
            offset: 0,
            fetching: true
          };
        case "fetch":
          return {
            ...state,
            error: null,
            data: action.data.hn.topStories,
            offset: state.offset + state.limit,
            fetching: false
          };
        case "start_fetch_more":
          return {
            ...state,
            fetchingMore: true
          };
        case "fetch_more":
          return {
            ...state,
            error: null,
            data: uniqBy([...state.data, ...action.data.hn.topStories], "id"),
            offset: state.offset + state.limit,
            fetchingMore: false
          };
        default:
          throw action;
      }
    },
    {
      data: [],
      error: null,
      offset: 0,
      limit: 30,
      fetching: false,
      fetchingMore: false
    }
  );

  useEffect(() => {
    dispatch({ type: "start_fetch" });
    urqlClient
      .query(newsListQuery, {
        limit: 30,
        offset: 0
      })
      .toPromise()
      .then(
        ({ data }) => {
          dispatch({ type: "fetch", data });
        },
        error => {
          dispatch({ type: "error", error });
        }
      );
  }, []);

  const refetch = () => {
    dispatch({ type: "start_fetch" });
    urqlClient
      .query(newsListQuery, {
        limit: 30,
        offset: 0
      })
      .toPromise()
      .then(
        ({ data }) => {
          dispatch({ type: "fetch", data });
        },
        error => {
          dispatch({ type: "error", error });
        }
      );
  };

  const fetchMore = () => {
    if (state.fetchingMore) {
      return;
    }
    dispatch({ type: "start_fetch_more" });

    urqlClient
      .query(newsListQuery, {
        limit: state.limit,
        offset: state.offset
      })
      .toPromise()
      .then(
        ({ data }) => {
          dispatch({ type: "fetch_more", data });
        },
        error => {
          dispatch({ type: "error", error });
        }
      );
  };

  return {
    data: state.data,
    error: state.error,
    fetching: state.fetching,
    fetchingMore: state.fetchingMore,
    refetch,
    fetchMore
  };
};

function ListItem({
  navigation,
  backgroundColor,
  story
}: {
  story: ItemT;
  navigation: NavigationScreenProp<{}, {}>;
  backgroundColor: string;
}) {
  return (
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
    >
      <NewsListItem backgroundColor={backgroundColor}>
        <TouchableOpacity
          style={{ flex: 1 }}
          onLongPress={() => {
            Share.share({
              title: story.title,
              url: story.url || makeHNUrl(story.id)
            });
          }}
          onPress={() => {
            if (story.url) {
              navigation.navigate({
                routeName: "Browser",
                params: { url: story.url }
              });
            } else {
              navigation.navigate({
                routeName: "Comments",
                params: { id: story.id, story }
              });
            }
          }}
        >
          <NewsListItemText>{story.title}</NewsListItemText>
        </TouchableOpacity>
        <Text style={styles.scoreText}>{story.score}</Text>
      </NewsListItem>
    </Swipeable>
  );
}

const MemoedListItem = memo(ListItem);

export const NewsList: React.FC<NewsListProps> = ({ navigation }) => {
  const {
    data: stories,
    fetching,
    error,
    fetchingMore,
    refetch,
    fetchMore
  } = useNewsListQuery();

  if (fetching) {
    return <Loader backgroundColor={d3.interpolateOranges(0.65)} />;
  }

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      indicatorStyle={"white"}
      onEndReachedThreshold={0.2}
      data={stories}
      refreshControl={
        <RefreshControl
          refreshing={fetching}
          onRefresh={() => refetch()}
          tintColor={"white"}
        />
      }
      ListFooterComponent={
        fetchingMore ? (
          <View style={{ padding }}>
            <Loader backgroundColor={backgroundDark} />
          </View>
        ) : null
      }
      onEndReached={() => fetchMore()}
      keyExtractor={item => item.id}
      renderItem={({ item: story, index }) => (
        <MemoedListItem
          story={story}
          key={story.id}
          navigation={navigation}
          backgroundColor={d3.interpolateOranges(
            (index / stories.length) * 0.35 + 0.65
          )}
        />
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
