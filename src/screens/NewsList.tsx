import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { memo, Suspense, useCallback, useMemo } from "react";
import {
  FlatList,
  ListRenderItem,
  RefreshControl,
  Text,
  View
} from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNStory } from "../common/types";
import { backgroundDark, backgroundOrange, padding } from "../common/vars";
import { Loader } from "../components/Loader";
// @ts-ignore
import { useInfiniteQuery } from "react-query";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ListItem } from "../components/ListItem";
import { flatten, uniq, uniqBy } from "lodash-es";
import { fetchNewsList } from "../fetchers/fetchNewsList";

interface NewsListProps {
  navigation: NavigationScreenProp<{}, {}>;
}

const MemoedListItem = memo(ListItem);

const getBackgroundColor = (index: number): string =>
  d3.interpolateOranges((index / 50) * 0.35 + 0.65);

export const NewsList: React.FC<NewsListProps> = ({ navigation }) => {
  const {
    refetch,
    data,
    isFetching,
    fetchMore,
    isFetchingMore
  } = useInfiniteQuery("news-list", fetchNewsList, {
    suspense: true,
    getFetchMore: (lastGroup: HNStory[], allGroups: HNStory[][]) => allGroups.length
  });

  const stories = data as HNStory[][];

  const flattenedStories = useMemo(() => uniqBy(flatten(stories), story => story.id), [stories]);

  const renderItem: ListRenderItem<HNStory> = useCallback(
    ({ item: story, index }) => {
      return (
        <MemoedListItem
          story={story}
          key={story.id}
          navigation={navigation}
          backgroundColor={getBackgroundColor(index)}
        />
      );
    },
    [navigation]
  );

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      indicatorStyle={"white"}
      data={flattenedStories}
      refreshControl={
        <RefreshControl
          refreshing={isFetching}
          onRefresh={() => refetch()}
          tintColor={"white"}
        />
      }
      ListFooterComponent={
        isFetchingMore ? (
          <View style={{ padding }}>
            <Loader backgroundColor={backgroundDark} />
          </View>
        ) : null
      }
      onEndReached={() => fetchMore()}
      keyExtractor={item => item.id}
      renderItem={renderItem}
    />
  );
};

export const NewsListScreen: React.FC<NewsListProps> = ({ navigation }) => {
  return (
    <Suspense fallback={<Loader backgroundColor={backgroundOrange} />}>
      <ErrorBoundary
        fallback={error => (
          <Text style={{ color: "white" }}>{error.message}</Text>
        )}
      >
        <NewsList navigation={navigation} />
      </ErrorBoundary>
    </Suspense>
  );
};
