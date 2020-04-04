import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { memo, Suspense, useCallback, useMemo, useState } from "react";
import { FlatList, ListRenderItem, RefreshControl, View } from "react-native";
import { HNStory } from "../common/types";
import { backgroundDark, backgroundOrange, padding } from "../common/vars";
import { FullPageLoader } from "../components/FullPageLoader";
import { useInfiniteQuery } from "react-query";
import { ListItem } from "../components/ListItem";
import { fetchNewsList, Paginated } from "../fetchers/fetchNewsList";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ErrorView } from "../components/ErrorView";
import { FullPageView } from "../components/FullPageView";
import { flatMap } from "lodash-es";
import { RootStackParamList } from "../../App";
import { RouteProp } from "@react-navigation/native";
import { StackNavigationProp } from "@react-navigation/stack";

const MemoedListItem = memo(ListItem);

const getBackgroundColor = (index: number): string =>
  d3.interpolateOranges((index / 50) * 0.35 + 0.65);

export const NewsList: React.FC = () => {
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

  const flattenedStories = useMemo(() => flatMap(stories, page => page.data), [
    stories
  ]);

  const renderItem: ListRenderItem<HNStory> = useCallback(
    ({ item: story, index }) => {
      return (
        <MemoedListItem
          story={story}
          key={story.id}
          backgroundColor={getBackgroundColor(index)}
        />
      );
    },
    []
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

interface NewsListScreenProps {
  navigation: StackNavigationProp<RootStackParamList, "Home">;
  route: RouteProp<RootStackParamList, "Home">;
}

export const NewsListScreen: React.FC<NewsListScreenProps> = () => (
  <Suspense fallback={<FullPageLoader backgroundColor={backgroundOrange} />}>
    <ErrorBoundary
      fallback={error => (
        <FullPageView backgroundColor={backgroundDark}>
          <ErrorView error={error} />
        </FullPageView>
      )}
    >
      <NewsList />
    </ErrorBoundary>
  </Suspense>
);
