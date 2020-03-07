import * as React from "react";
import { useEffect, useState } from "react";
import { RefreshControl, ScrollView } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNComment, HNStory } from "../common/types";
import { backgroundDark } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { Loader } from "../components/FullPageLoader";
import { useQuery } from "react-query";
import {
  fetchCommentsForItem,
  HNStoryWithComments
} from "../fetchers/fetchCommentsForItem";
import { FullPageView } from "../components/FullPageView";
import { EmptyCommentsView } from "../components/EmptyCommentsView";
import { CommentsFlatList } from "../components/CommentsFlatList";

export const CommentsList: React.FC<{
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;
  const [isRefreshing, setRefreshing] = useState(false);

  const [mounted, setMounted] = useState(false);

  const { data: story, isFetching, refetch } = useQuery<
    HNStoryWithComments,
    any
  >(
    ["comments", { id }],
    // @ts-ignore
    fetchCommentsForItem,
    {
      onSettled: () => setRefreshing(false),
      refetchOnWindowFocus: false
    }
  );

  const onRefresh = () => {
    setRefreshing(true);
    refetch();
  };

  useEffect(() => {
    setMounted(true);
  }, []);

  const comments = story?.kids.filter(
    (kid: HNComment | null) => kid && !!kid.text
  ) as HNComment[];

  const showFullPageSpinner =
    !mounted || (!story && isFetching && !isRefreshing);

  if (showFullPageSpinner || comments.length == 0) {
    return (
      <ScrollView
        contentContainerStyle={{ flex: 1 }}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={"white"}
          />
        }
      >
        {navigation.state.params!.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params!.story}
          />
        )}
        <FullPageView backgroundColor={backgroundDark}>
          {showFullPageSpinner ? <Loader /> : <EmptyCommentsView />}
        </FullPageView>
      </ScrollView>
    );
  }

  return (
    <CommentsFlatList
      story={story}
      navigation={navigation}
      comments={comments}
      isRefreshing={isRefreshing}
      refetch={onRefresh}
    />
  );
};
