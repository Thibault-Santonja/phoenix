defmodule PortfolioWeb.ArticleComponentsTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolioWeb.Components.ArticleCard
  alias PortfolioWeb.Components.ArticleCodeBloc
  alias PortfolioWeb.Components.ArticleSection
  alias PortfolioWeb.Components.BlogArticle

  describe "article_card/1" do
    test "renders article card with required attributes" do
      html =
        render_component(&ArticleCard.article_card/1,
          url: "/blog/test-article",
          icon: "hero-document-text",
          title: "Test Article",
          description: "This is a test description",
          card_class: "",
          header_class: ""
        )

      assert html =~ "href=\"/blog/test-article\""
      assert html =~ "Test Article"
      assert html =~ "This is a test description"
    end

    test "renders article card with icon" do
      html =
        render_component(&ArticleCard.article_card/1,
          url: "/blog/test",
          icon: "hero-code-bracket",
          title: "Code Article",
          description: "Description",
          card_class: "",
          header_class: ""
        )

      assert html =~ "hero-code-bracket"
    end

    test "renders article card with custom classes" do
      html =
        render_component(&ArticleCard.article_card/1,
          url: "/blog/test",
          icon: "hero-star",
          title: "Styled Article",
          description: "Description",
          card_class: "custom-card-class",
          header_class: "custom-header-class"
        )

      assert html =~ "custom-card-class"
      assert html =~ "custom-header-class"
    end

    test "article card has hover and transition styles" do
      html =
        render_component(&ArticleCard.article_card/1,
          url: "/blog/test",
          icon: "hero-star",
          title: "Article",
          description: "Description",
          card_class: "",
          header_class: ""
        )

      assert html =~ "hover:shadow-md"
      assert html =~ "transition-all"
      assert html =~ "duration-300"
    end

    test "article card renders as anchor tag" do
      html =
        render_component(&ArticleCard.article_card/1,
          url: "/blog/test",
          icon: "hero-star",
          title: "Article",
          description: "Description",
          card_class: "",
          header_class: ""
        )

      assert html =~ "<a"
      assert html =~ "</a>"
    end
  end

  describe "article_card_list/1" do
    test "renders article card list with title" do
      html =
        render_component(&ArticleCard.article_card_list/1,
          title: "Latest Articles",
          article_card: [],
          card_class: "",
          header_class: ""
        )

      assert html =~ "Latest Articles"
      assert html =~ "<article"
    end

    test "renders multiple article cards in list" do
      cards = [
        %{url: "/blog/first", title: "First", description: "Desc 1", icon: "hero-star"},
        %{url: "/blog/second", title: "Second", description: "Desc 2", icon: "hero-heart"}
      ]

      html =
        render_component(&ArticleCard.article_card_list/1,
          title: "Articles",
          article_card: cards,
          card_class: "",
          header_class: ""
        )

      assert html =~ "First"
      assert html =~ "Second"
      assert html =~ "id=\"article-card-1\""
      assert html =~ "id=\"article-card-2\""
    end

    test "renders grid layout" do
      html =
        render_component(&ArticleCard.article_card_list/1,
          title: "Articles",
          article_card: [],
          card_class: "",
          header_class: ""
        )

      assert html =~ "grid"
      assert html =~ "grid-cols-1"
      assert html =~ "sm:grid-cols-2"
      assert html =~ "lg:grid-cols-3"
    end

    test "applies custom card and header classes to all cards" do
      cards = [
        %{url: "/blog/test", title: "Test", description: "Desc", icon: "hero-star"}
      ]

      html =
        render_component(&ArticleCard.article_card_list/1,
          title: "Articles",
          article_card: cards,
          card_class: "shared-card-class",
          header_class: "shared-header-class"
        )

      assert html =~ "shared-card-class"
      assert html =~ "shared-header-class"
    end

    test "renders empty list without errors" do
      html =
        render_component(&ArticleCard.article_card_list/1,
          title: "Empty List",
          article_card: [],
          card_class: "",
          header_class: ""
        )

      assert html =~ "Empty List"
      assert html =~ "<ul"
    end
  end

  describe "article_section/1" do
    test "renders section with title" do
      html =
        render_component(&ArticleSection.article_section/1,
          title: "My Section",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "My Section"
      assert html =~ "<h2"
      assert html =~ "<article"
    end

    test "renders section with custom id" do
      html =
        render_component(&ArticleSection.article_section/1,
          id: "custom-section-id",
          title: "Section",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "id=\"custom-section-id\""
    end

    test "renders inner block content" do
      html =
        render_component(&ArticleSection.article_section/1,
          title: "Section",
          inner_block: [
            %{__slot__: :inner_block, inner_block: fn _, _ -> "Inner block content here" end}
          ]
        )

      assert html =~ "Inner block content here"
    end

    test "has prose styling for typography" do
      html =
        render_component(&ArticleSection.article_section/1,
          title: "Section",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "prose"
    end

    test "renders without id when not provided" do
      html =
        render_component(&ArticleSection.article_section/1,
          title: "Section",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      # Should have article tag but no specific id attribute value
      assert html =~ "<article"
    end
  end

  describe "blog_article/1" do
    test "renders blog article with title" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "My Blog Post",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Article content" end}]
        )

      assert html =~ "My Blog Post"
      assert html =~ "<h1"
      assert html =~ "<section"
    end

    test "renders blog article with overview" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "Post Title",
          overview: "This is the overview text",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "This is the overview text"
      assert html =~ "italic"
    end

    test "does not render overview paragraph when nil" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "Post Title",
          overview: nil,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      # Should not have the italic overview paragraph
      refute html =~ "italic"
    end

    test "renders inner block content" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "Post",
          inner_block: [
            %{__slot__: :inner_block, inner_block: fn _, _ -> "Main article content" end}
          ]
        )

      assert html =~ "Main article content"
    end

    test "has card-like styling" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "Post",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "rounded-lg"
      assert html =~ "border"
      assert html =~ "shadow-lg"
    end

    test "title has uppercase styling" do
      html =
        render_component(&BlogArticle.blog_article/1,
          title: "Post",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "uppercase"
    end
  end

  describe "code_bloc/1" do
    test "renders code block with pre tag" do
      html =
        render_component(&ArticleCodeBloc.code_bloc/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "code here" end}]
        )

      assert html =~ "<pre"
      assert html =~ "</pre>"
    end

    test "renders inner block content" do
      html =
        render_component(&ArticleCodeBloc.code_bloc/1,
          inner_block: [
            %{__slot__: :inner_block, inner_block: fn _, _ -> "const x = 42;" end}
          ]
        )

      assert html =~ "const x = 42;"
    end

    test "has code styling classes" do
      html =
        render_component(&ArticleCodeBloc.code_bloc/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "code" end}]
        )

      assert html =~ "rounded-lg"
      assert html =~ "overflow-auto"
      assert html =~ "text-sm"
    end
  end
end
