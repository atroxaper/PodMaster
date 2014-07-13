module Pod::SAX::Goes::HTML {
	use Pod::SAX::Reformer;
	use Pod::SAX::Anchors;
	use Pod::SAX::Common;
	use Pod::SAX::Iter;

	my $N = "\n";

	my %simple-format =
		C => 'code',
		I => 'em',
		B => 'strong',
		R => 'var';

	# I stole that sub from L<Pod::To::HTML module|https://github.com/perl6/Pod-To-HTML>
	sub escape_html(Str $str) returns Str {
		return $str unless $str ~~ /<[&<>"']>/;

		$str.trans( [ q{&},     q{<},    q{>},    q{"},      q{'}     ] =>
					[ q{&amp;}, q{&lt;}, q{&gt;}, q{&quot;}, q{&#39;} ] );
	}

	# I stole that sub from L<Pod::To::HTML module|https://github.com/perl6/Pod-To-HTML>
	sub escape_id ($id) {
		$id.subst(/\s+/, '_', :g);
	}

	#| Sub renders a Table of Contents.
	#| It find in %storage<toc> an Array with triples (level, href_id, to_display_text)
	sub render-toc(:%storage) {
		return True, '' unless %storage<toc>;
		my @result;
		my @with-headers = @(%storage<toc>);

		my $c-level = 0;
		push @result, '<nav class="indexgroup">';
		for @with-headers -> @head {
			my $n-level = @head[0];
			# render <ol> and </ol> #
			loop (my $i = $c-level + 1; $i <= $n-level; ++$i) {
				@result.push(qq[<ol class="indexList indexList{$i}">]);
			}
			loop ($i = $c-level; $i > $n-level; --$i) {
				@result.push(q[</ol>]);
			}
			$c-level = $n-level;
			# render <li><a></a></li> #
			@result.push(qq[<li class="indexItem indexItem{$c-level}"><a href="#{@head[1]}">{@head[2]}</a></li>]);
		}
		# last </ol>s #
		loop (my $i = $c-level; $i > 0; --$i) {
			@result.push(q[</ol>]);
		}
		push @result, "</nav>";
		return True, @result.join;
	}

	my (@comment, @named, @para, @table, @formatting, @heading, @code) = ();

	# =comment #
	push @comment,
		:() => {
			in => { say qq[find comment: $:content]; }
		};
	# start of html #
	push @named,
		:(:$name where 'pod') => {
			start => {
				append(
					qq[<!doctype html>{$N}<html>{$N}<head>{$N}],
					SimpleAnchor.new(:template(qq[<title><%=TITLE%></title>{$N}])),
					qq[<link href="index.css" type="text/css" rel="stylesheet">{$N}],
					qq[</head>{$N}<body class="pod" id="___top">{$N}]
				);
			},
			stop => {
				append(qq[</body>{$N}</html>{$N}]);
			}
		};
	# =head #
	push @heading,
		:() => {
			start => {
				my $bare = get-bare-content($:instance);
				my $bare-id = escape_id($bare);
				append qq[<h$:level id="{$bare-id}">];
				my @toc = @(%:storage<toc>) || ();
				@toc[+@toc] = $:level, $bare-id, $bare;
				%:storage<toc> = @toc;
			},
			stop => { append qq[</h$:level>]; }
		};
	push @para,
		:(:@history where *.&under-type(Pod::Heading)) => {
			start => { True },
			in => {
				append qq[<a class="u" href="#___top" title="go to top document">$:content\</a>];
			},
			stop => { True }
		};
	# =TITLE #
	push @para,
		:(:@history where *.&under-name('TITLE')) => {
			start => { append q[<h1>]; },
			in => {
				append $:content;
				%:storage{'TITLE'} = $:content;
			},
			stop => {
				append qq[</h1>{$N}];
				# TOC should be after the title of page #
				my $toc = CallbackAnchor.new(:callback(&render-toc), :priority(1));
				append $toc;
			}
		};
	# =VERSION and =AUTHOR #
	push @named,
		:(:$name where 'VERSION' | 'AUTHOR') => {
			start => { append qq[<section>{$N}<h1>$:name\</h1>{$N}]; },
			stop =>  { append qq[</section>{$N}]; }
		};
	# =output #
	push @named,
		:(:$name where 'output') => {
			start => { append q[<samp>]; },
			stop =>  { append q[</samp>]; }
		};
	push @para,
		:(:@history where *.&under-name('output')) => {
			start => { True; },
			in =>    { append $:content },
			stop =>  { append q[</br>]; }
		};
	# =table #
	push @table,
		:() => {
			start => {
				append qq[<table>{$N}];
				# render headers #
				if (@:headers && +@:headers > 0) {
					append qq[<thead>{$N}<tr>{$N}];
					for @headers -> $header {
						append qq[<th>{$header}</th>{$N}];
					}
					append qq[</tr>{$N}</thead>{$N}];
				}

				append qq[<tbody>{$N}];
			},
			in => {
				append qq[<tr>{$N}];
				for @($:content) -> $td {
					append qq[<td>{$td}</td>{$N}];
				}
				append qq[</tr>{$N}];
			},
			stop => { append qq[</tbody>{$N}</table>{$N}]; }
		};
	# L<> #
	push @formatting,
		:(:$type where 'L') => {
			start => sub (:$instance, :@meta) {
				my $good-meta;
				if @meta {
					$good-meta = @meta[0];
				} else { # if meta is't declared than we get bare content
			 		$good-meta = get-bare-content($instance);
			 	}
			 	# parse scheme
			 	# maybe it would better to write special Action for that
			 	my $m = MetaL.parse($good-meta);
			 	if ($m<scheme> && $m<scheme><type> eq 'doc' && $m<intern>) {
			 		$good-meta = "$m<intern>";
			 	} elsif ($m<scheme> && $m<scheme><type> eq 'defn') {
			 		sub test(:%storage, :%custom) {
						my $search = %custom<search>;
						my $found = %storage{$search} || '_defn_' ~ $search;
						return True, '#' ~ $found;
					}
					my %custom = search => "$m<extern>";
					$good-meta = CallbackAnchor.new(:callback(&test), :custom(%custom));
			 	} elsif ($m<scheme> && $m<scheme><type> ~~ any('http', 'https')
			 			&& $m<extern> && $m<extern><from-root>.from == $m<extern><from-root>.to) {
			 		$good-meta = "$m<extern><path>";
			 		$good-meta ~= "$m<intern>" if $m<intern>;
			 	}
			 	$good-meta = escape_id($good-meta) if $good-meta ~~ Str;

				append q[<a href="], $good-meta, q[">];
			},
			in => {
				append $:content;
			},
			stop => { append qq[</a>]; }
		};
	# D<> #
	push @formatting,
		:(:$type where 'D') => {
			start => { append qq[{$N}<dfn id="]; },
			in => {
				my $id = '_defn_' ~ escape_id($:content);
				append qq[{$id}">];
				append $:content;
				%:storage{$:content} = $id;
				%:storage{$_} = $id for @:meta;
			},
			stop => { append qq[</dfn>]; }
		}
	# C<> I<> B<> R<> #
	push @formatting,
		:(:$type where 'C' | 'I' | 'B' | 'R') => {
			start => { my $tag = %simple-format{$:type}; append qq[<{$tag}>]; },
			in => { append escape_html($:content); },
			stop =>  { my $tag = %simple-format{$:type}; append qq[</{$tag}>]; }
		};
	# General Paragraph #
	push @para,
		:() => {
			start => { append "<p>"; },
			in => { append $:content; },
			stop => { append "</p>{$N}"; }
		};
	# =code #
	push @code,
		:() => {
			start => { append qq[<pre>]; },
			in => { append escape_html($:content); },
			stop => { append qq[</pre>]; }
		};

	sub make-reformer() is export {
		my Reformer $reformer .= new;
		$reformer.callbacks{Pod::Block::Comment.^name} = @comment;
		$reformer.callbacks{Pod::Block::Named.^name} = @named;
		$reformer.callbacks{Pod::Block::Para.^name} = @para;
		$reformer.callbacks{Pod::Block::Table.^name} = @table;
		$reformer.callbacks{Pod::FormattingCode.^name} = @formatting;
		$reformer.callbacks{Pod::Heading.^name} = @heading;
		$reformer.callbacks{Pod::Block::Code.^name} = @code;

		return $reformer;
	}
}
