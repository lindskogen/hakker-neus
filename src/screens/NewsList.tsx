import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { memo, Suspense, useCallback, useMemo, useState } from "react";
import {
  FlatList,
  ListRenderItem,
  RefreshControl,
  Text,
  View
} from "react-native";
import { HNStory } from "../common/types";
import { backgroundDark, backgroundOrange, padding } from "../common/vars";
import { FullPageLoader } from "../components/FullPageLoader";
// @ts-ignore
import { useInfiniteQuery } from "react-query";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ListItem } from "../components/ListItem";
import { fetchNewsList, Paginated } from "../fetchers/fetchNewsList";
import { StackNavigationProp } from "react-navigation-stack/src/vendor/types";

interface NewsListProps {
  navigation: StackNavigationProp<{}, {}>;
}

const MemoedListItem = memo(ListItem);

const getBackgroundColor = (index: number): string =>
  d3.interpolateOranges((index / 50) * 0.35 + 0.65);

export const NewsList: React.FC<NewsListProps> = ({ navigation }) => {
  const [isRefetching, setRefetching] = useState(false);
  const { refetch, data, fetchMore, isFetchingMore } = useInfiniteQuery(
    "news-list",
    fetchNewsList,
    {
      suspense: true,
      refetchOnMount: false,
      onSettled: () => setRefetching(false),
      refetchOnWindowFocus: false,
      getFetchMore: (lastPage: any) => lastPage.nextPage
    }
  );

  const stories = data as Paginated<HNStory[]>[];

  const flattenedStories = useMemo(() => stories.flatMap(page => page.data), [
    stories
  ]);

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
          refreshing={isRefetching}
          onRefresh={() => {
            setRefetching(true);
            refetch();
          }}
          tintColor={"white"}
        />
      }
      ListFooterComponent={
        isFetchingMore ? (
          <View style={{ padding }}>
            <FullPageLoader backgroundColor={backgroundDark} />
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
    <Suspense fallback={<FullPageLoader backgroundColor={backgroundOrange} />}>
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
