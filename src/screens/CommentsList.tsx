import * as React from "react";
import { useMemo, useState } from "react";
import { RefreshControl, ScrollView } from "react-native";
import { FlatHNComment, HNComment, HNStory } from "../common/types";
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
import { flatMap } from "lodash-es";
import { StackNavigationProp } from "react-navigation-stack/lib/typescript/src/vendor/types";
import { isDefined } from "../lib/isDefined";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ErrorView } from "../components/ErrorView";

export const flattenComments = (
  comments: HNComment[],
  depth: number = 0
): FlatHNComment[] =>
  flatMap(comments, comment => {
    if (comment && comment.text) {
      return [
        { comment, depth },
        ...flattenComments(comment?.kids ?? [], depth + 1)
      ];
    } else {
      return flattenComments(comment?.kids ?? [], depth + 1);
    }
  });

const InnerCommentsList: React.FC<{
  navigation: StackNavigationProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;
  const [isRefreshing, setRefreshing] = useState(false);

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

  const comments = useMemo(
    () =>
      story?.kids.filter(
        (kid: HNComment | null) => kid && !!kid.text
      ) as HNComment[],
    [story]
  );

  const flatComments = useMemo(
    () => flattenComments(comments).filter(isDefined),
    [comments]
  );

  const showFullPageSpinner = !story && isFetching && !isRefreshing;

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
      comments={flatComments}
      isRefreshing={isRefreshing}
      refetch={onRefresh}
    />
  );
};

export const CommentsList: React.FC<{
  navigation: StackNavigationProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  return (
    <ErrorBoundary
      fallback={error => (
        <ScrollView contentContainerStyle={{ flex: 1 }}>
          {navigation.state.params!.story && (
            <CommentsListItemHeader
              navigation={navigation}
              story={navigation.state.params!.story}
            />
          )}
          <FullPageView backgroundColor={backgroundDark}>
            <ErrorView error={error} />
          </FullPageView>
        </ScrollView>
      )}
    >
      <InnerCommentsList navigation={navigation} />
    </ErrorBoundary>
  );
};
