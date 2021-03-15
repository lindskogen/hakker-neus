import * as d3 from "d3-scale-chromatic";
import * as React from "react";
import { memo, Suspense, useMemo } from "react";
import {
  FlatList,
  ListRenderItem,
  RefreshControl,
  StyleSheet,
  View,
} from "react-native";
import { HNStory } from "../common/types";
import { backgroundDark, backgroundOrange, padding } from "../common/vars";
import { FullPageLoader } from "../components/FullPageLoader";
import { ListItem } from "../components/ListItem";
import { useNewsList } from "../fetchers/fetchNewsList";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ErrorView } from "../components/ErrorView";
import { FullPageView } from "../components/FullPageView";
import { RootStackParamList } from "../../App";
import { RouteProp } from "@react-navigation/native";
import { StackNavigationProp } from "@react-navigation/stack";

const MemoedListItem = memo(ListItem);

const getBackgroundColor = (index: number): string =>
  d3.interpolateOranges((index / 50) * 0.35 + 0.65);

const renderItem: ListRenderItem<HNStory> = ({ item: story, index }) => (
  <MemoedListItem
    story={story}
    key={story.id}
    backgroundColor={getBackgroundColor(index)}
  />
);

export const NewsList: React.FC = () => {
  const {
    onRefresh,
    isRefetching,
    stories,
    fetchMore,
    isFetchingMore,
  } = useNewsList();

  const refreshControl = useMemo(
    () => (
      <RefreshControl
        refreshing={isRefetching}
        onRefresh={onRefresh}
        tintColor={"white"}
      />
    ),
    [isRefetching, onRefresh]
  );

  return (
    <FlatList<HNStory>
      style={styles.scrollView}
      indicatorStyle={"white"}
      data={stories}
      ItemSeparatorComponent={SeparatorComponent}
      refreshControl={refreshControl}
      ListFooterComponent={
        isFetchingMore ? (
          <View style={styles.footer}>
            <FullPageLoader backgroundColor={backgroundDark} />
          </View>
        ) : null
      }
      onEndReached={fetchMore}
      keyExtractor={keyExtractor}
      renderItem={renderItem}
    />
  );
};

const keyExtractor = (item: HNStory) => item.id;

const SeparatorComponent = () => <View style={styles.separator} />;

const styles = StyleSheet.create({
  scrollView: { backgroundColor: backgroundDark },
  separator: { borderBottomWidth: StyleSheet.hairlineWidth },
  footer: { padding },
});

interface NewsListScreenProps {
  navigation: StackNavigationProp<RootStackParamList, "Home">;
  route: RouteProp<RootStackParamList, "Home">;
}

export const NewsListScreen: React.FC<NewsListScreenProps> = () => (
  <Suspense fallback={<FullPageLoader backgroundColor={backgroundOrange} />}>
    <ErrorBoundary
      fallback={(error) => (
        <FullPageView backgroundColor={backgroundDark}>
          <ErrorView error={error} />
        </FullPageView>
      )}
    >
      <NewsList />
    </ErrorBoundary>
  </Suspense>
);
