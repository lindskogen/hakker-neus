import * as React from "react";
import { useMemo } from "react";
import { RefreshControl, ScrollView } from "react-native";
import { FlatHNComment, HNComment, HNStory } from "../common/types";
import { backgroundDark } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { Loader } from "../components/FullPageLoader";
import { useHNItemWithComments } from "../fetchers/fetchCommentsForItem";
import { FullPageView } from "../components/FullPageView";
import { EmptyCommentsView } from "../components/EmptyCommentsView";
import { CommentsFlatList } from "../components/CommentsFlatList";
import { flatMap } from "lodash-es";
import { StackNavigationProp } from "@react-navigation/stack";
import { isDefined } from "../lib/isDefined";
import { ErrorBoundary } from "../components/ErrorBoundary";
import { ErrorView } from "../components/ErrorView";
import { RootStackParamList } from "../../App";
import { RouteProp } from "@react-navigation/native";

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

const InnerCommentsList: React.FC<{ id: string; story?: HNStory }> = props => {
  const { story, isRefreshing, isFetching, onRefresh } = useHNItemWithComments(props.id);

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
        {props.story && <CommentsListItemHeader story={props.story} />}
        <FullPageView backgroundColor={backgroundDark}>
          {showFullPageSpinner ? <Loader /> : <EmptyCommentsView />}
        </FullPageView>
      </ScrollView>
    );
  }

  return (
    <CommentsFlatList
      story={story!}
      comments={flatComments}
      isRefreshing={isRefreshing}
      refetch={onRefresh}
    />
  );
};

interface CommentsListProps {
  navigation: StackNavigationProp<RootStackParamList, "Comments">;
  route: RouteProp<RootStackParamList, "Comments">;
}

export const CommentsList: React.FC<CommentsListProps> = ({ route }) => {
  return (
    <ErrorBoundary
      fallback={error => (
        <ScrollView contentContainerStyle={{ flex: 1 }}>
          {route.params.story && (
            <CommentsListItemHeader story={route.params.story} />
          )}
          <FullPageView backgroundColor={backgroundDark}>
            <ErrorView error={error} />
          </FullPageView>
        </ScrollView>
      )}
    >
      <InnerCommentsList id={route.params.id} story={route.params.story} />
    </ErrorBoundary>
  );
};
