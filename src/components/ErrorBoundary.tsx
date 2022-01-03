import "../lib/enableErrorReporting";
import Bugsnag from "@bugsnag/expo";
import * as React from "react";
import { ReactNode } from "react";

interface Props {
  fallback: (error: Error) => ReactNode;
  onError?: (error: Error, componentStack: string) => void;
}

const BugsnagErrorBoundary = Bugsnag.getPlugin("react");

export const ErrorBoundary: React.FC<Props> = (props) => {
  const { children, fallback } = props;
  return (
    <BugsnagErrorBoundary
      FallbackComponent={({ error }: { error: Error }) => (
        <>{fallback(error)}</>
      )}
    >
      {children}
    </BugsnagErrorBoundary>
  );
};
