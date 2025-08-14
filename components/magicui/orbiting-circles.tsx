import { cn } from "@/lib/utils";
import React, { createContext, forwardRef, useContext, useMemo } from "react";

// OrbitingCircles component
interface OrbitingCirclesProps extends React.HTMLAttributes<HTMLDivElement> {
  className?: string;
  children?: React.ReactNode;
  /**
   *  The radius of the circles.
   */
  radius?: number;
  /**
   * The duration of the animation in seconds.
   */
  duration?: number;
  /**
   * The delay of the animation in seconds.
   */
  delay?: number;
  /**
   * The path of the circles.
   * @default true
   */
  path?: boolean;
  /**
   * The direction of the animation.
   * @default "normal"
   */
  reverse?: boolean;
}

const OrbitingCircles = ({
  className,
  children,
  reverse,
  duration = 20,
  delay = 10,
  radius = 50,
  path = true,
}: OrbitingCirclesProps) => {
  return (
    <>
      {path && (
        <div
          style={
            {
              "--radius": radius,
              "--duration": duration,
            } as React.CSSProperties
          }
          className="absolute flex h-full w-full transform-gpu animate-orbit items-center justify-center rounded-full border bg-black/10 [animation-delay:calc(var(--delay)*-1s)] dark:bg-white/10"
        >
          <div className="absolute h-full w-full rounded-full border-none" />
        </div>
      )}

      <div
        style={
          {
            "--radius": radius,
            "--duration": duration,
            "--delay": delay,
          } as React.CSSProperties
        }
        className={cn(
          "absolute flex h-full w-full transform-gpu animate-orbit items-center justify-center [animation-delay:calc(var(--delay)*-1s)]",
          { "[animation-direction:reverse]": reverse },
          className,
        )}
      >
        {children}
      </div>
    </>
  );
};

// OrbitingCirclesItem component
interface OrbitingCirclesItemProps extends React.HTMLAttributes<HTMLDivElement> {
  className?: string;
  children?: React.ReactNode;
  /**
   * The duration of the animation in seconds.
   */
  duration?: number;
  /**
   * The radius of the circles.
   */
  radius?: number;
  /**
   * The delay of the animation in seconds.
   */
  delay?: number;
  /**
   * The direction of the animation.
   * @default "normal"
   */
  reverse?: boolean;
}
const OrbitingCirclesItem = ({
  className,
  children,
  reverse,
  duration = 20,
  delay = 10,
  radius = 50,
}: OrbitingCirclesItemProps) => {
  return (
    <div
      style={
        {
          "--radius": radius,
          "--duration": duration,
          "--delay": delay,
        } as React.CSSProperties
      }
      className={cn(
        "absolute flex h-full w-full transform-gpu animate-orbit-item items-center justify-center [animation-delay:calc(var(--delay)*-1s)]",
        { "[animation-direction:reverse]": reverse },
        className,
      )}
    >
      {children}
    </div>
  );
};

export default OrbitingCircles;
export { OrbitingCirclesItem };
